import Foundation

public struct VerifiedFindingsReplayReport: Sendable, Codable, Equatable {
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
        if let bridged = replayWithRust(recovered) {
            return bridged
        }
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

    private static func replayWithRust(
        _ recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsReplayReport? {
        let request = ReviewCoreReplayRequest(
            schemaVersion: 1,
            envelope: recovered.envelope,
            checkpointSource: recovered.source.rawValue
        )
        let response: ReviewCoreReplayBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_replay_verified_findings",
            request: request
        )
        return response?.report
    }
}

private struct ReviewCoreReplayRequest: Encodable {
    let schemaVersion: Int
    let envelope: VerifiedFindingsSessionEnvelope
    let checkpointSource: String
}

private struct ReviewCoreReplayBridgeResponse: Decodable {
    let report: VerifiedFindingsReplayReport?
}
