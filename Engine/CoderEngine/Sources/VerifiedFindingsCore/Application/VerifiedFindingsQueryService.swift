import Foundation

public enum VerifiedFindingsQueryKind: String, Sendable, Codable, Equatable {
    case candidate
    case verified
}

public struct VerifiedFindingsQuery: Sendable, Equatable {
    public let kind: VerifiedFindingsQueryKind
    public let domain: VerifiedFindingDomain?
    public let severity: String?
    public let status: String?
    public let sourceOrigin: String?
    public let category: String?
    public let file: String?
    public let limit: Int
    public let includeSensitiveDetails: Bool

    public init(
        kind: VerifiedFindingsQueryKind = .verified,
        domain: VerifiedFindingDomain? = nil,
        severity: String? = nil,
        status: String? = nil,
        sourceOrigin: String? = nil,
        category: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false
    ) {
        self.kind = kind
        self.domain = domain
        self.severity = severity
        self.status = status
        self.sourceOrigin = sourceOrigin
        self.category = category
        self.file = file
        self.limit = limit
        self.includeSensitiveDetails = includeSensitiveDetails
    }
}

public enum VerifiedFindingsQueryService {
    public static func listPayloads(
        snapshot: CodeReviewSessionSnapshot,
        query: VerifiedFindingsQuery,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> [[String: String]] {
        let resolved = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint)
        return listPayloads(resolved: resolved, query: query)
    }

    public static func listPayloads(
        resolved: VerifiedFindingsResolvedState,
        query: VerifiedFindingsQuery
    ) -> [[String: String]] {
        let findings = resolved.recovered.envelope.canonicalSnapshot.findings.values
            .filter { finding in
                let matchesKind: Bool = switch query.kind {
                case .candidate:
                    finding.status == .candidate || finding.status == .verifying
                case .verified:
                    !(finding.status == .candidate || finding.status == .verifying)
                }
                guard matchesKind else { return false }
                if let domain = query.domain, finding.domain != domain { return false }
                if let severity = query.severity, !severity.isEmpty, finding.severity.rawValue != severity { return false }
                if let status = query.status, !status.isEmpty, finding.status.rawValue != status { return false }
                if let sourceOrigin = query.sourceOrigin, !sourceOrigin.isEmpty, finding.sourceOrigin != sourceOrigin { return false }
                if let category = query.category, !category.isEmpty, finding.category != category { return false }
                if let file = query.file, !file.isEmpty, !finding.filePath.contains(file) { return false }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence { return lhs.id < rhs.id }
                return lhs.confidence > rhs.confidence
            }

        return Array(findings.prefix(query.limit)).map { finding in
            var payload: [String: String] = [
                "id": finding.id,
                "kind": query.kind.rawValue,
                "severity": finding.severity.rawValue,
                "category": finding.category,
                "domain": finding.domain.rawValue,
                "status": finding.status.rawValue,
                "stale_status": finding.staleStatus.rawValue,
            ]
            if let sourceOrigin = finding.sourceOrigin {
                payload["origin"] = sourceOrigin
            }
            if !finding.possibleDuplicateOf.isEmpty {
                payload["possible_duplicate_of"] = finding.possibleDuplicateOf.joined(separator: ",")
            }
            if let mergedIntoFindingId = finding.mergedIntoFindingId {
                payload["merged_into_finding_id"] = mergedIntoFindingId
            }
            if let recurrenceGroupId = finding.recurrenceGroupId {
                payload["recurrence_group_id"] = recurrenceGroupId
            }
            payload["confidence"] = String(format: "%.2f", finding.confidence)

            if query.includeSensitiveDetails {
                payload["file_path"] = finding.filePath
                payload["message"] = finding.title
                if let lineStart = finding.lineStart { payload["line_number"] = String(lineStart) }
                if let lineEnd = finding.lineEnd { payload["end_line_number"] = String(lineEnd) }
            } else {
                payload["file_label"] = MCPSharedState.stableRedactionSuffix(for: finding.filePath)
                payload["message_summary"] = finding.title
                if let lineStart = finding.lineStart { payload["line_number"] = String(lineStart) }
            }
            return payload
        }
    }
}
