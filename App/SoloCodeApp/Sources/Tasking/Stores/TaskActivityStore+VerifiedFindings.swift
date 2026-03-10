import Foundation
import CoderEngine

extension TaskActivityStore {
    func resolvedVerifiedFindingsState(
        for snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> VerifiedFindingsResolvedState {
        let recovered: VerifiedFindingsRecoveredEnvelope
        if let envelope = snapshot.verifiedFindings {
            recovered = VerifiedFindingsRecoveredEnvelope(
                source: .embeddedSnapshot,
                envelope: envelope,
                checkpoint: nil
            )
        } else {
            let existingEnvelope = verifiedFindingsEnvelope(
                sessionId: snapshot.sessionId,
                conversationId: conversationId
            )
            recovered = VerifiedFindingsRecoveredEnvelope(
                source: .syncedFromSnapshot,
                envelope: VerifiedFindingsSessionSyncService.sync(
                    snapshot: snapshot,
                    existingEnvelope: existingEnvelope,
                    entryPoint: .reviewChat
                ),
                checkpoint: nil
            )
        }
        return VerifiedFindingsService.resolve(recovered: recovered)
    }

    func resolvedVerifiedFindingsProjection(
        for snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> VerifiedFindingsProjectionSnapshot {
        resolvedVerifiedFindingsState(
            for: snapshot,
            conversationId: conversationId
        ).recovered.envelope.projectionSnapshot
    }

    func verifiedFindingsEnvelope(
        sessionId: String?,
        conversationId: UUID?
    ) -> VerifiedFindingsSessionEnvelope? {
        guard let sessionId else {
            return codeReviewSnapshot(sessionId: nil, conversationId: conversationId)?.verifiedFindings
        }
        if let envelope = verifiedFindingsEnvelopesBySession[sessionId] {
            return envelope
        }
        if let envelope = codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )?.verifiedFindings {
            return envelope
        }
        return MCPSharedState.readVerifiedFindingsEnvelope(sessionId: sessionId)
    }

    func verifiedFindingsProjection(for conversationId: UUID?) -> VerifiedFindingsProjectionSnapshot {
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            guard let snapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId) else {
                return emptyVerifiedFindingsProjection()
            }
            return resolvedVerifiedFindingsProjection(
                for: snapshot,
                conversationId: conversationId
            )
        }
        if let projection = verifiedFindingsProjectionsByConversation[conversationScope] {
            return projection
        }
        guard let snapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId) else {
            return emptyVerifiedFindingsProjection()
        }
        return resolvedVerifiedFindingsProjection(
            for: snapshot,
            conversationId: conversationId
        )
    }

    func codeReviewPayload(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?,
        verifiedState: VerifiedFindingsResolvedState? = nil
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
        let verifiedState = verifiedState ?? resolvedVerifiedFindingsState(
            for: snapshot,
            conversationId: conversationId
        )
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
