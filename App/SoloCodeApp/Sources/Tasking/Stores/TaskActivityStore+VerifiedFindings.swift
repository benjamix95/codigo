import Foundation
import CoderEngine

extension TaskActivityStore {
    func reviewPanelDerivedState(
        sessionId: String?,
        conversationId: UUID?
    ) -> ReviewPanelDerivedState? {
        if let sessionId,
           let derivedState = reviewPanelDerivedStateBySession[sessionId] {
            return derivedState
        }
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return nil
        }
        return reviewPanelDerivedStateByConversation[conversationScope]
    }

    func updateReviewPanelDerivedState(
        _ derivedState: ReviewPanelDerivedState,
        conversationId: UUID?
    ) {
        reviewPanelDerivedStateBySession[derivedState.sessionId] = derivedState
        if let conversationScope = codeReviewConversationScope(conversationId) {
            reviewPanelDerivedStateByConversation[conversationScope] = derivedState
        }
    }

    func removeReviewPanelDerivedState(
        sessionId: String,
        conversationId: UUID?
    ) {
        reviewPanelDerivedStateBySession.removeValue(forKey: sessionId)
        if let conversationScope = codeReviewConversationScope(conversationId) {
            let replacement = codeReviewSessionIdsByConversation[conversationScope]?
                .compactMap { reviewPanelDerivedStateBySession[$0] }
                .sorted(by: {
                    if $0.mutationSequence != $1.mutationSequence {
                        return $0.mutationSequence > $1.mutationSequence
                    }
                    return $0.sessionId > $1.sessionId
                })
                .first
            reviewPanelDerivedStateByConversation[conversationScope] = replacement
        }
        ReviewPanelDerivedStateBuilder.invalidate(sessionId: sessionId)
    }

    func deriveReviewPanelState(
        snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> ReviewPanelDerivedState {
        let derivedState = ReviewPanelDerivedStateBuilder.build(
            snapshot: snapshot,
            existingEnvelope: verifiedFindingsEnvelopesBySession[snapshot.sessionId]
        )
        updateReviewPanelDerivedState(derivedState, conversationId: conversationId)
        return derivedState
    }

    func resolvedVerifiedFindingsState(
        for snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?,
        allowPersistenceRead: Bool = false
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
                conversationId: conversationId,
                allowPersistenceRead: allowPersistenceRead
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
        conversationId: UUID?,
        allowPersistenceRead: Bool = true
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
        guard allowPersistenceRead else { return nil }
        return MCPSharedState.readVerifiedFindingsEnvelope(sessionId: sessionId)
    }

    func verifiedFindingsProjection(for conversationId: UUID?) -> VerifiedFindingsProjectionSnapshot {
        if let derivedState = reviewPanelDerivedState(sessionId: nil, conversationId: conversationId) {
            return derivedState.projection
        }
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
        verifiedState: VerifiedFindingsResolvedState? = nil,
        derivedState: ReviewPanelDerivedState? = nil
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
        if let derivedState {
            let projection = derivedState.projection
            payload["verified_candidate_queue_count"] = String(projection.candidateQueue.count)
            payload["verified_queue_count"] = String(projection.verifiedQueue.count)
            payload["verified_duplicates_count"] = String(projection.duplicatesCount)
            payload["verified_stale_candidates_count"] = String(projection.staleCandidatesCount)
            payload["verified_envelope_source"] = derivedState.verifiedEnvelope == nil ? "unavailable" : "embedded_snapshot"
            payload["verified_replay_candidate_count"] = String(projection.candidateQueue.count)
            payload["verified_replay_findings_count"] = String(projection.verifiedQueue.count)
            payload["verified_security_gate_ready"] = "true"
        } else {
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
        }
        let reviewCoreState = ReviewCoreBridge.loadedState()
        payload["review_core_loaded"] = reviewCoreState.loaded ? "true" : "false"
        if let version = reviewCoreState.version {
            payload["review_core_version"] = version
        }
        if let reason = reviewCoreState.failureReason {
            payload["review_core_failure_reason"] = reason
        }
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
