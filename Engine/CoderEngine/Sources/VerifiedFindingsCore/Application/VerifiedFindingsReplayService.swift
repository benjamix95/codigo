import Foundation

public struct VerifiedFindingsReplayReport: Sendable, Equatable {
    public let sessionId: String
    public let checkpointSource: VerifiedFindingsEnvelopeSource
    public let eventSchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let findingCount: Int
    public let eventCount: Int
    public let traceCount: Int
    public let candidateCount: Int
    public let verifiedCount: Int
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
}

public enum VerifiedFindingsReplayService {
    public static func replay(
        sessionId: String
    ) -> VerifiedFindingsReplayReport? {
        guard let recovered = VerifiedFindingsCheckpointService.rebuildEnvelope(sessionId: sessionId) else {
            return nil
        }
        return replay(recovered)
    }

    public static func replay(
        _ recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsReplayReport {
        let projection = VerifiedFindingsProjectionBuilder.build(
            from: recovered.envelope.canonicalSnapshot
        )
        return VerifiedFindingsReplayReport(
            sessionId: recovered.envelope.sessionId,
            checkpointSource: recovered.source,
            eventSchemaVersion: recovered.envelope.eventSchemaVersion,
            projectionSchemaVersion: recovered.envelope.projectionSchemaVersion,
            entitySchemaVersion: recovered.envelope.entitySchemaVersion,
            findingCount: recovered.envelope.canonicalSnapshot.findings.count,
            eventCount: recovered.envelope.canonicalSnapshot.eventLog.count,
            traceCount: recovered.envelope.canonicalSnapshot.traceLog.count,
            candidateCount: projection.candidateQueue.count,
            verifiedCount: projection.verifiedQueue.count,
            duplicatesCount: projection.duplicatesCount,
            staleCandidatesCount: projection.staleCandidatesCount
        )
    }
}
