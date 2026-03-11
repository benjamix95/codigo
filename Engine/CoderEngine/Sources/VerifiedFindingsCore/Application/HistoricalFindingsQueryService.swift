import Foundation

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

public enum HistoricalFindingsQueryService {
    public static func list(
        query: HistoricalFindingsQuery
    ) -> [HistoricalFindingRecord] {
        guard let store = MCPSharedState.persistenceStoreIfAvailable() else { return [] }
        let records = (try? store.readHistoricalFindings(query: query)) ?? []
        return shapeWithRust(records) ?? records
    }

    public static func detail(
        findingId: String,
        workspaceId: String
    ) -> HistoricalFindingRecord? {
        guard let store = MCPSharedState.persistenceStoreIfAvailable() else { return nil }
        let record = try? store.readHistoricalFinding(
            findingId: findingId,
            workspaceId: workspaceId
        )
        guard let record else { return nil }
        return shapeWithRust([record])?.first ?? record
    }

    private static func shapeWithRust(
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
