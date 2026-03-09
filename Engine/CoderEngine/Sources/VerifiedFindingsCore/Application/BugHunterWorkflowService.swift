import Foundation

public struct BugHunterClusterSummary: Sendable, Equatable {
    public let title: String
    public let size: Int
    public let files: [String]
    public let averageConfidence: Double
    public let primaryRisk: String
}

public enum BugHunterWorkflowService {
    public static func makeStartRequest(
        runId: String,
        reviewSessionId: String,
        sourceKind: MCPSharedBugHunterSourceKind,
        againstRef: String?,
        prompt: String,
        maxRounds: Int,
        maxWorkers: Int,
        conversationId: UUID? = nil
    ) throws -> VerifiedFindingsStartCommandRequest {
        try VerifiedFindingsStartCommandService.makeRequest(
            args: [
                "scope": againstRef == nil ? "uncommitted" : "against_ref",
                "ref": againstRef ?? "",
                "session_id": reviewSessionId,
                "analysis_only": "false",
                "max_rounds": String(maxRounds),
                "max_workers": String(maxWorkers),
                "bughunter_run_id": runId,
                "bughunter_profile": sourceKind == .commit ? "commit_review" : "deep",
                "bughunter_prompt_override": prompt,
            ],
            conversationId: conversationId
        )
    }

    public static func findings(
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

    public static func selectAutofixFindingId(
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

    public static func explainCluster(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> BugHunterClusterSummary? {
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint)
        return explainCluster(resolved: resolved)
    }

    public static func explainCluster(
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

    public static func queueLifecycleCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        switch action {
        case "apply_patch":
            return try VerifiedFindingsLifecycleCommandService.queueApplyPatchCommand(
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        default:
            return try VerifiedFindingsLifecycleCommandService.queueFindingCommand(
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        }
    }
}
