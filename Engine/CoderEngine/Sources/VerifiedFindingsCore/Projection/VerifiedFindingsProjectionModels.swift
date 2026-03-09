import Foundation

public struct VerifiedFindingListItemProjection: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let domain: VerifiedFindingDomain
    public let status: VerifiedFindingStatus
    public let staleStatus: VerifiedFindingStaleStatus
    public let severity: VerifiedFindingSeverity
    public let filePath: String
    public let lineStart: Int?
    public let duplicateOf: [String]
    public let mergedIntoFindingId: String?
    public let recurrenceGroupId: String?

    public init(
        id: String,
        title: String,
        domain: VerifiedFindingDomain,
        status: VerifiedFindingStatus,
        staleStatus: VerifiedFindingStaleStatus,
        severity: VerifiedFindingSeverity,
        filePath: String,
        lineStart: Int?,
        duplicateOf: [String],
        mergedIntoFindingId: String?,
        recurrenceGroupId: String?
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.status = status
        self.staleStatus = staleStatus
        self.severity = severity
        self.filePath = filePath
        self.lineStart = lineStart
        self.duplicateOf = duplicateOf
        self.mergedIntoFindingId = mergedIntoFindingId
        self.recurrenceGroupId = recurrenceGroupId
    }
}

public struct VerifiedFindingsProjectionSnapshot: Sendable, Codable, Equatable {
    public let candidateQueue: [VerifiedFindingListItemProjection]
    public let verifiedQueue: [VerifiedFindingListItemProjection]
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
    public let traceSnippets: [String]

    public init(
        candidateQueue: [VerifiedFindingListItemProjection],
        verifiedQueue: [VerifiedFindingListItemProjection],
        duplicatesCount: Int,
        staleCandidatesCount: Int,
        traceSnippets: [String]
    ) {
        self.candidateQueue = candidateQueue
        self.verifiedQueue = verifiedQueue
        self.duplicatesCount = duplicatesCount
        self.staleCandidatesCount = staleCandidatesCount
        self.traceSnippets = traceSnippets
    }
}
