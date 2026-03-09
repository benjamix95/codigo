import Foundation

public struct VerifiedFindingsResolvedState: Sendable, Equatable {
    public let recovered: VerifiedFindingsRecoveredEnvelope
    public let securityGate: VerifiedFindingsSecurityGateReport
    public let replayReport: VerifiedFindingsReplayReport

    public init(
        recovered: VerifiedFindingsRecoveredEnvelope,
        securityGate: VerifiedFindingsSecurityGateReport,
        replayReport: VerifiedFindingsReplayReport
    ) {
        self.recovered = recovered
        self.securityGate = securityGate
        self.replayReport = replayReport
    }
}

public enum VerifiedFindingsService {
    public static func resolve(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsResolvedState {
        let recovered = VerifiedFindingsCheckpointService.resolveEnvelope(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        return resolve(recovered: recovered)
    }

    public static func resolve(
        sessionId: String,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsResolvedState? {
        if let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) {
            return resolve(snapshot: snapshot, entryPoint: entryPoint)
        }
        guard let recovered = VerifiedFindingsCheckpointService.rebuildEnvelope(sessionId: sessionId) else {
            return nil
        }
        return resolve(recovered: recovered)
    }

    public static func resolve(
        recovered: VerifiedFindingsRecoveredEnvelope
    ) -> VerifiedFindingsResolvedState {
        VerifiedFindingsResolvedState(
            recovered: recovered,
            securityGate: VerifiedFindingsSecurityGateService.evaluate(
                envelope: recovered.envelope
            ),
            replayReport: VerifiedFindingsReplayService.replay(recovered)
        )
    }

    public static func projection(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsProjectionSnapshot {
        resolve(snapshot: snapshot, entryPoint: entryPoint).recovered.envelope.projectionSnapshot
    }

    public static func canonicalSnapshot(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsCanonicalSnapshot {
        resolve(snapshot: snapshot, entryPoint: entryPoint).recovered.envelope.canonicalSnapshot
    }
}
