import Foundation
import CoderEngine

extension TaskActivityStore {
    func verifiedFindingsEnvelope(
        sessionId: String?,
        conversationId: UUID?
    ) -> VerifiedFindingsSessionEnvelope? {
        if let sessionId,
           let envelope = verifiedFindingsEnvelopesBySession[sessionId] {
            return envelope
        }
        return codeReviewSnapshot(sessionId: sessionId, conversationId: conversationId)?.verifiedFindings
    }

    func verifiedFindingsProjection(for conversationId: UUID?) -> VerifiedFindingsProjectionSnapshot {
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewSnapshot(sessionId: nil, conversationId: conversationId)?.verifiedFindingsProjection
                ?? emptyVerifiedFindingsProjection()
        }
        return verifiedFindingsProjectionsByConversation[conversationScope]
            ?? codeReviewSnapshot(sessionId: nil, conversationId: conversationId)?.verifiedFindingsProjection
            ?? emptyVerifiedFindingsProjection()
    }

    func codeReviewPayload(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> [String: String] {
        var payload: [String: String] = [
            "phase": snapshot.phase.rawValue,
            "findings_count": String(snapshot.findings.count),
            "candidates_count": String(snapshot.candidates.count),
            "patches_count": String(snapshot.patches.count),
            "open_count": String(snapshot.openFindings.count),
            "round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
        ]
        payload["patches_applied"] = String(snapshot.outcome.patchesApplied)
        payload["prs_opened"] = String(snapshot.outcome.prsOpened)
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
        }
        if let error = snapshot.lastError {
            payload["error"] = error
        }
        let verifiedState = VerifiedFindingsService.resolve(snapshot: snapshot)
        let projection = verifiedState.recovered.envelope.projectionSnapshot
        payload["verified_candidate_queue_count"] = String(projection.candidateQueue.count)
        payload["verified_queue_count"] = String(projection.verifiedQueue.count)
        payload["verified_duplicates_count"] = String(projection.duplicatesCount)
        payload["verified_stale_candidates_count"] = String(projection.staleCandidatesCount)
        payload["verified_envelope_source"] = verifiedState.recovered.source.rawValue
        payload["verified_replay_candidate_count"] = String(verifiedState.replayReport.candidateCount)
        payload["verified_replay_findings_count"] = String(verifiedState.replayReport.verifiedCount)
        payload["verified_security_gate_ready"] = verifiedState.securityGate.ready ? "true" : "false"
        if let conversationScope = codeReviewConversationScope(conversationId) {
            payload["conversation_id"] = conversationScope
        }
        payload["session_id"] = snapshot.sessionId
        payload["stage"] = snapshot.stage.rawValue
        return payload
    }

    func emptyVerifiedFindingsProjection() -> VerifiedFindingsProjectionSnapshot {
        VerifiedFindingsProjectionSnapshot(
            candidateQueue: [],
            verifiedQueue: [],
            duplicatesCount: 0,
            staleCandidatesCount: 0,
            traceSnippets: []
        )
    }
}
