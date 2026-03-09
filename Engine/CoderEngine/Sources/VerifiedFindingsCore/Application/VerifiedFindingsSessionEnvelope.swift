import Foundation

public struct VerifiedFindingsSessionEnvelope: Sendable, Codable, Equatable {
    public let sessionId: String
    public let canonicalSnapshot: VerifiedFindingsCanonicalSnapshot
    public let projectionSnapshot: VerifiedFindingsProjectionSnapshot
    public let eventSchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let lastUpdatedAt: Date

    public init(
        sessionId: String,
        canonicalSnapshot: VerifiedFindingsCanonicalSnapshot,
        projectionSnapshot: VerifiedFindingsProjectionSnapshot,
        eventSchemaVersion: Int = 1,
        projectionSchemaVersion: Int = 1,
        entitySchemaVersion: Int = 1,
        lastUpdatedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.canonicalSnapshot = canonicalSnapshot
        self.projectionSnapshot = projectionSnapshot
        self.eventSchemaVersion = eventSchemaVersion
        self.projectionSchemaVersion = projectionSchemaVersion
        self.entitySchemaVersion = entitySchemaVersion
        self.lastUpdatedAt = lastUpdatedAt
    }
}
