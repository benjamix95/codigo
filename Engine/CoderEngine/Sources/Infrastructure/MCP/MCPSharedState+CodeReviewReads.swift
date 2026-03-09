import Foundation

extension MCPSharedState {
    public static func readCodeReviewFindings(
        sessionId: String,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        origin: String? = nil,
        category: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false
    ) -> [[String: String]] {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else { return [] }
        let normalizedKind = (kind ?? "verified").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: normalizedKind == "candidate" || normalizedKind == "candidates" ? .candidate : .verified,
                domain: nil,
                severity: severity,
                status: status,
                sourceOrigin: origin,
                category: category.map { FindingCategory.fromStoredValue($0).rawValue },
                file: file,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            ),
            entryPoint: .mcp
        )
    }

    public static func readCodeReviewStatus(sessionId: String) -> [String: String]? {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else { return nil }
        return VerifiedFindingsStatusService.payload(snapshot: snapshot, entryPoint: .mcp)
    }
}
