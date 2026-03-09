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
}

public struct VerifiedFindingsProjectionSnapshot: Sendable, Codable, Equatable {
    public let candidateQueue: [VerifiedFindingListItemProjection]
    public let verifiedQueue: [VerifiedFindingListItemProjection]
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
    public let traceSnippets: [String]
}
