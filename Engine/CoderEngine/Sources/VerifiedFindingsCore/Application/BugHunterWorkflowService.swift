import Foundation

public struct BugHunterClusterSummary: Sendable, Equatable {
    public let title: String
    public let size: Int
    public let files: [String]
    public let averageConfidence: Double
    public let primaryRisk: String
}

public enum BugHunterWorkflowService {
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
}
