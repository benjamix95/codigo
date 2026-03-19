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

public struct HistoricalFindingTimelineItem: Sendable, Codable, Identifiable, Equatable {
    public let eventId: String
    public let eventType: String
    public let detail: String?
    public let createdAt: Date
    public let metadata: [String: String]

    public var id: String { eventId }

    public init(
        eventId: String,
        eventType: String,
        detail: String?,
        createdAt: Date,
        metadata: [String: String]
    ) {
        self.eventId = eventId
        self.eventType = eventType
        self.detail = detail
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct HistoricalFindingRecord: Sendable, Codable, Identifiable, Equatable {
    public let findingId: String
    public let sessionId: String
    public let workspaceId: String
    public let domain: VerifiedFindingDomain
    public let severity: VerifiedFindingSeverity
    public let title: String
    public let summary: String
    public let status: VerifiedFindingStatus
    public let filePath: String
    public let lineStart: Int?
    public let sourceOrigin: String?
    public let closedReason: String?
    public let patchId: String?
    public let patchApplyStatus: VerifiedPatchApplyStatus?
    public let revalidationReportId: String?
    public let revalidationVerdict: RevalidationVerdict?
    public let createdAt: Date
    public let updatedAt: Date
    public let resolvedAt: Date?
    public let resumeEligible: Bool
    public let timeline: [HistoricalFindingTimelineItem]

    public var id: String { findingId }

    public init(
        findingId: String,
        sessionId: String,
        workspaceId: String,
        domain: VerifiedFindingDomain,
        severity: VerifiedFindingSeverity,
        title: String,
        summary: String,
        status: VerifiedFindingStatus,
        filePath: String,
        lineStart: Int?,
        sourceOrigin: String?,
        closedReason: String?,
        patchId: String?,
        patchApplyStatus: VerifiedPatchApplyStatus?,
        revalidationReportId: String?,
        revalidationVerdict: RevalidationVerdict?,
        createdAt: Date,
        updatedAt: Date,
        resolvedAt: Date?,
        resumeEligible: Bool,
        timeline: [HistoricalFindingTimelineItem]
    ) {
        self.findingId = findingId
        self.sessionId = sessionId
        self.workspaceId = workspaceId
        self.domain = domain
        self.severity = severity
        self.title = title
        self.summary = summary
        self.status = status
        self.filePath = filePath
        self.lineStart = lineStart
        self.sourceOrigin = sourceOrigin
        self.closedReason = closedReason
        self.patchId = patchId
        self.patchApplyStatus = patchApplyStatus
        self.revalidationReportId = revalidationReportId
        self.revalidationVerdict = revalidationVerdict
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.resumeEligible = resumeEligible
        self.timeline = timeline
    }
}

public struct HistoricalFindingsQuery: Sendable, Equatable {
    public let workspaceId: String
    public let limit: Int

    public init(workspaceId: String, limit: Int = 200) {
        self.workspaceId = workspaceId
        self.limit = max(1, min(limit, 500))
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
                payload["file_label"] = redactedFileLabel(for: finding.filePath)
                payload["message_summary"] = redactedFindingSummary(for: finding)
                if let lineStart = finding.lineStart { payload["line_number"] = String(lineStart) }
            }
            return payload
        }
    }

    private static func redactedFileLabel(for filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let fileClass = ext.isEmpty ? "file" : "\(ext)-file"
        return "redacted-\(fileClass)-\(MCPSharedState.stableRedactionSuffix(for: filePath))"
    }

    private static func redactedFindingSummary(for finding: VerifiedFinding) -> String {
        let category = finding.category.replacingOccurrences(of: "_", with: " ")
        return "Redacted \(finding.severity.rawValue) \(category) finding"
    }

    public static func listHistoricalFindings(
        query: HistoricalFindingsQuery
    ) -> [HistoricalFindingRecord] {
        guard let store = MCPSharedState.persistenceStoreIfAvailable() else { return [] }
        let records = (try? store.readHistoricalFindings(query: query)) ?? []
        return shapeHistoricalFindingsWithRust(records) ?? records
    }

    public static func historicalFindingDetail(
        findingId: String,
        workspaceId: String
    ) -> HistoricalFindingRecord? {
        guard let store = MCPSharedState.persistenceStoreIfAvailable() else { return nil }
        let record = try? store.readHistoricalFinding(
            findingId: findingId,
            workspaceId: workspaceId
        )
        guard let record else { return nil }
        return shapeHistoricalFindingsWithRust([record])?.first ?? record
    }

    private static func shapeHistoricalFindingsWithRust(
        _ records: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord]? {
        let request = ReviewCoreHistoricalShapeRequest(
            schemaVersion: 1,
            records: records
        )
        let response: ReviewCoreHistoricalShapeBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_shape_historical_findings",
            request: request
        )
        return response?.mergedHistory
    }
}

struct ReviewCoreHistoricalShapeRequest: Encodable {
    let schemaVersion: Int
    let records: [HistoricalFindingRecord]
}

struct ReviewCoreHistoricalShapeBridgeResponse: Decodable {
    let mergedHistory: [HistoricalFindingRecord]?
}
