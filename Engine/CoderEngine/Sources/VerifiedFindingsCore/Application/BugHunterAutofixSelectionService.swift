import Foundation

public struct BugHunterClusterSummary: Sendable, Equatable {
    public let title: String
    public let size: Int
    public let files: [String]
    public let averageConfidence: Double
    public let primaryRisk: String
}

public enum BugHunterWorkflowService {}

public enum BugHunterAutofixSelectionService {
    public static func selectFindingId(
        from resolvedState: VerifiedFindingsResolvedState,
        minimumConfidence: Double = 0.9
    ) -> String? {
        resolvedState.recovered.envelope.canonicalSnapshot.findings.values
            .filter { finding in
                finding.domain == .bug
                    && finding.status == .verified
                    && finding.confidence >= minimumConfidence
                    && finding.mergedIntoFindingId == nil
            }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.confidence > rhs.confidence
            }
            .first?.id
    }
}

public extension BugHunterWorkflowService {
    static func findings(
        snapshot: CodeReviewSessionSnapshot,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> [[String: String]] {
        VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: (kind ?? "verified").lowercased() == "candidate" ? .candidate : .verified,
                domain: .bug,
                severity: severity,
                status: status,
                sourceOrigin: "bugHunter",
                category: nil,
                file: nil,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            ),
            entryPoint: entryPoint
        )
    }

    static func selectAutofixFindingId(
        snapshot: CodeReviewSessionSnapshot,
        minimumConfidence: Double = 0.9,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> String? {
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint)
        return BugHunterAutofixSelectionService.selectFindingId(
            from: resolved,
            minimumConfidence: minimumConfidence
        )
    }

    static func explainCluster(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> BugHunterClusterSummary? {
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint)
        return explainCluster(resolved: resolved)
    }

    static func explainCluster(
        resolved: VerifiedFindingsResolvedState
    ) -> BugHunterClusterSummary? {
        let findings = resolved.recovered.envelope.canonicalSnapshot.findings.values
            .filter { $0.domain == .bug }
        guard !findings.isEmpty else { return nil }
        let grouped = Dictionary(grouping: findings) { finding in
            finding.title.split(separator: ".").first.map(String.init) ?? finding.title
        }
        guard let top = grouped.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let files = Array(Set(top.value.map(\.filePath))).sorted()
        let averageConfidence = top.value.map(\.confidence).reduce(0, +) / Double(max(top.value.count, 1))
        return BugHunterClusterSummary(
            title: top.key,
            size: top.value.count,
            files: files,
            averageConfidence: averageConfidence,
            primaryRisk: top.value.first?.category ?? "unknown"
        )
    }
}

public struct VerifiedFindingsPipelineStatus: Sendable, Equatable {
    public let pipelinePhase: String
    public let progressPercent: Int
    public let stepsTotal: Int
    public let stepsCompleted: Int
    public let toolsTotal: Int
    public let toolsCompleted: Int
    public let toolsRunning: Int
    public let verificationGateReady: Bool
    public let patchGateReady: Bool
    public let publishReady: Bool
    public let bundleModes: [String]
    public let candidateCount: Int
    public let verifiedCount: Int
    public let publishedFindingCount: Int
}

public enum VerifiedFindingsPipelineStatusService {
    public static func evaluate(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsPipelineStatus {
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint)
        let projection = resolved.recovered.envelope.projectionSnapshot
        let verifiedIds = Set(projection.verifiedQueue.map(\.id))
        let bundleModes = bundleModes(for: snapshot)
        let toolsTotal = max(snapshot.audit.toolCoverage.count, bundleModes.count)
        let toolsCompleted = snapshot.audit.toolCoverage.count
        let toolsRunning = snapshot.isActive
            ? min(max(snapshot.activeWorkerCount, 1), max(toolsTotal - toolsCompleted, 0))
            : 0

        let verificationGateReady = verificationGateReady(snapshot: snapshot, verifiedIds: verifiedIds)
        let patchGateReady = patchGateReady(snapshot: snapshot, verifiedIds: verifiedIds)
        let publishedFindingCount = snapshot.findings.filter {
            isPublishedFinding($0, in: snapshot, verifiedIds: verifiedIds)
        }.count
        let publishReady = verificationGateReady && patchGateReady && snapshot.phase != .idle
        let pipelinePhase = pipelinePhase(
            snapshot: snapshot,
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            verificationGateReady: verificationGateReady,
            patchGateReady: patchGateReady,
            publishReady: publishReady
        )

        return VerifiedFindingsPipelineStatus(
            pipelinePhase: pipelinePhase,
            progressPercent: progressPercent(
                pipelinePhase: pipelinePhase,
                snapshot: snapshot,
                verifiedIds: verifiedIds,
                toolsTotal: toolsTotal,
                toolsCompleted: toolsCompleted
            ),
            stepsTotal: 6,
            stepsCompleted: stepsCompleted(for: pipelinePhase),
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            toolsRunning: toolsRunning,
            verificationGateReady: verificationGateReady,
            patchGateReady: patchGateReady,
            publishReady: publishReady,
            bundleModes: bundleModes,
            candidateCount: projection.candidateQueue.count,
            verifiedCount: projection.verifiedQueue.count,
            publishedFindingCount: publishedFindingCount
        )
    }

    private static func bundleModes(for snapshot: CodeReviewSessionSnapshot) -> [String] {
        guard snapshot.startedAt != nil || snapshot.phase != .idle || !snapshot.events.isEmpty else {
            return []
        }
        return ["standard", "bugFinder", "securityAudit"]
    }

    private static func verificationGateReady(
        snapshot: CodeReviewSessionSnapshot,
        verifiedIds: Set<String>
    ) -> Bool {
        guard !verifiedIds.isEmpty else {
            return snapshot.phase == .completed || snapshot.findings.isEmpty
        }
        let findingsById = Dictionary(uniqueKeysWithValues: snapshot.findings.map { ($0.id, $0) })
        return verifiedIds.allSatisfy { id in
            guard let finding = findingsById[id] else { return false }
            return finding.verifiedAt != nil || finding.verificationReport != nil
        }
    }

    private static func patchGateReady(
        snapshot: CodeReviewSessionSnapshot,
        verifiedIds: Set<String>
    ) -> Bool {
        guard !verifiedIds.isEmpty else {
            return snapshot.phase == .completed || snapshot.findings.isEmpty
        }
        let findingsById = Dictionary(uniqueKeysWithValues: snapshot.findings.map { ($0.id, $0) })
        let patchesByFindingId = Dictionary(uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) })
        return verifiedIds.allSatisfy { id in
            guard let finding = findingsById[id] else { return false }
            return hasPatchReady(for: finding, patchesByFindingId: patchesByFindingId)
        }
    }

    private static func isPublishedFinding(
        _ finding: CodeReviewFinding,
        in snapshot: CodeReviewSessionSnapshot,
        verifiedIds: Set<String>
    ) -> Bool {
        guard verifiedIds.contains(finding.id) else { return false }
        let patchesByFindingId = Dictionary(uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) })
        let isVerified = finding.verifiedAt != nil || finding.verificationReport != nil
        return isVerified && hasPatchReady(for: finding, patchesByFindingId: patchesByFindingId)
    }

    private static func hasPatchReady(
        for finding: CodeReviewFinding,
        patchesByFindingId: [String: ReviewPatchArtifact]
    ) -> Bool {
        guard let patchId = finding.patchArtifactId,
              let patch = patchesByFindingId[finding.id],
              patch.id == patchId else {
            return false
        }
        return patch.verifyStatus == .verified
            && [.verified, .applied, .prOpened, .merged].contains(patch.status)
    }

    private static func pipelinePhase(
        snapshot: CodeReviewSessionSnapshot,
        toolsTotal: Int,
        toolsCompleted: Int,
        verificationGateReady: Bool,
        patchGateReady: Bool,
        publishReady: Bool
    ) -> String {
        if snapshot.phase == .completed { return "completed" }
        if publishReady { return "publish_ready" }
        if verificationGateReady && !patchGateReady { return "patch_preparation" }
        if !verificationGateReady && (snapshot.analysisCompletedAt != nil || !snapshot.candidates.isEmpty || !snapshot.findings.isEmpty) {
            return "verification"
        }
        if toolsTotal > 0 && toolsCompleted > 0 { return "audit" }
        if snapshot.startedAt != nil || snapshot.phase == .analyzing { return "discovery" }
        return "queued"
    }

    private static func stepsCompleted(for pipelinePhase: String) -> Int {
        switch pipelinePhase {
        case "completed": return 6
        case "publish_ready": return 5
        case "patch_preparation": return 4
        case "verification": return 3
        case "audit": return 2
        case "discovery": return 1
        default: return 0
        }
    }

    private static func progressPercent(
        pipelinePhase: String,
        snapshot: CodeReviewSessionSnapshot,
        verifiedIds: Set<String>,
        toolsTotal: Int,
        toolsCompleted: Int
    ) -> Int {
        switch pipelinePhase {
        case "completed":
            return 100
        case "publish_ready":
            return 90
        case "patch_preparation":
            let readyPatches = snapshot.findings.filter { finding in
                isPublishedFinding(finding, in: snapshot, verifiedIds: verifiedIds)
            }.count
            let total = max(verifiedIds.count, 1)
            return 65 + Int((Double(readyPatches) / Double(total)) * 23.0)
        case "verification":
            let verified = snapshot.findings.filter {
                verifiedIds.contains($0.id) && ($0.verifiedAt != nil || $0.verificationReport != nil)
            }.count
            let total = max(verifiedIds.count, max(snapshot.findings.count, 1))
            return 45 + Int((Double(verified) / Double(total)) * 20.0)
        case "audit":
            let total = max(toolsTotal, 1)
            return 20 + Int((Double(toolsCompleted) / Double(total)) * 20.0)
        case "discovery":
            return toolsCompleted > 0 ? 18 : 8
        default:
            return snapshot.startedAt == nil ? 0 : 4
        }
    }
}
