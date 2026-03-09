import Foundation

public enum VerifiedFindingsEnvelopeSource: String, Sendable, Codable, Equatable {
    case embeddedSnapshot = "embedded_snapshot"
    case storedEnvelope = "stored_envelope"
    case rebuiltFromCanonical = "rebuilt_from_canonical"
    case syncedFromSnapshot = "synced_from_snapshot"
}

public struct VerifiedFindingsRecoveredEnvelope: Sendable, Equatable {
    public let source: VerifiedFindingsEnvelopeSource
    public let envelope: VerifiedFindingsSessionEnvelope
    public let checkpoint: MCPSharedVerifiedFindingsCheckpoint?

    public init(
        source: VerifiedFindingsEnvelopeSource,
        envelope: VerifiedFindingsSessionEnvelope,
        checkpoint: MCPSharedVerifiedFindingsCheckpoint?
    ) {
        self.source = source
        self.envelope = envelope
        self.checkpoint = checkpoint
    }
}

public enum VerifiedFindingsCheckpointService {
    public static func loadCanonicalSnapshot(
        sessionId: String
    ) -> VerifiedFindingsCanonicalSnapshot? {
        MCPSharedState.readVerifiedFindingsCanonicalSnapshot(sessionId: sessionId)
    }

    public static func loadCheckpoint(
        sessionId: String
    ) -> MCPSharedVerifiedFindingsCheckpoint? {
        MCPSharedState.readVerifiedFindingsCheckpoint(sessionId: sessionId)
    }

    public static func rebuildEnvelope(
        sessionId: String
    ) -> VerifiedFindingsRecoveredEnvelope? {
        guard let canonical = loadCanonicalSnapshot(sessionId: sessionId) else { return nil }
        let checkpoint = loadCheckpoint(sessionId: sessionId)
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            eventSchemaVersion: checkpoint?.eventSchemaVersion ?? 1,
            projectionSchemaVersion: checkpoint?.projectionSchemaVersion ?? 1,
            entitySchemaVersion: checkpoint?.entitySchemaVersion ?? 1,
            lastUpdatedAt: checkpoint?.checkpointedAt ?? Date()
        )
        return VerifiedFindingsRecoveredEnvelope(
            source: .rebuiltFromCanonical,
            envelope: envelope,
            checkpoint: checkpoint
        )
    }

    public static func resolveEnvelope(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsRecoveredEnvelope {
        if let envelope = snapshot.verifiedFindings {
            return VerifiedFindingsRecoveredEnvelope(
                source: .embeddedSnapshot,
                envelope: envelope,
                checkpoint: loadCheckpoint(sessionId: snapshot.sessionId)
            )
        }
        if let storedEnvelope = MCPSharedState.readVerifiedFindingsEnvelope(sessionId: snapshot.sessionId) {
            return VerifiedFindingsRecoveredEnvelope(
                source: .storedEnvelope,
                envelope: storedEnvelope,
                checkpoint: loadCheckpoint(sessionId: snapshot.sessionId)
            )
        }
        if let rebuilt = rebuildEnvelope(sessionId: snapshot.sessionId) {
            return rebuilt
        }
        let synced = VerifiedFindingsSessionSyncService.sync(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        return VerifiedFindingsRecoveredEnvelope(
            source: .syncedFromSnapshot,
            envelope: synced,
            checkpoint: nil
        )
    }
}
