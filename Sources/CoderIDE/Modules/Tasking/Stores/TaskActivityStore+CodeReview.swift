import Foundation
import CoderEngine

extension TaskActivityStore {
    // MARK: - Code Review Session Integration

    /// Ingests a CodeReviewSessionSnapshot and publishes relevant activities
    /// for LiveCard display. Called from the `CodeReviewSessionState.onStateChange` callback.
    func ingestCodeReviewSnapshot(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID? = nil
    ) {
        if let current = codeReviewSnapshotsBySession[snapshot.sessionId] {
            if snapshot.mutationSequence < current.mutationSequence {
                return
            }
            if snapshot.mutationSequence == current.mutationSequence,
               snapshot.lastUpdatedAt < current.lastUpdatedAt {
                return
            }
        }
        codeReviewSnapshotsBySession[snapshot.sessionId] = snapshot

        let resolvedConversationId = conversationId ?? snapshot.conversationId
        if let conversationScope = codeReviewConversationScope(resolvedConversationId) {
            var sessionIds = codeReviewSessionIdsByConversation[conversationScope] ?? []
            let isNewSession = !sessionIds.contains(snapshot.sessionId)
            sessionIds.removeAll { $0 == snapshot.sessionId }
            sessionIds.insert(snapshot.sessionId, at: 0)
            codeReviewSessionIdsByConversation[conversationScope] = sessionIds
            if isNewSession || selectedCodeReviewSessionIdByConversation[conversationScope] == nil {
                selectedCodeReviewSessionIdByConversation[conversationScope] = snapshot.sessionId
            }
        }

        // Update structured data for panel consumption
        codeReviewFindings = snapshot.findings
        codeReviewEvents = snapshot.events
        codeReviewPhase = snapshot.phase
        codeReviewStage = snapshot.stage
        if let conversationScope = codeReviewConversationScope(resolvedConversationId) {
            codeReviewFindingsByConversation[conversationScope] = snapshot.findings
            codeReviewEventsByConversation[conversationScope] = snapshot.events
            codeReviewPhaseByConversation[conversationScope] = snapshot.phase
        }

        // Persist to disk for MCP server cross-process reads (review_status, review_findings)
        MCPSharedState.writeCodeReviewSnapshot(snapshot)

        let activity = TaskActivity(
            type: "code_review_update",
            title: codeReviewTitle(for: snapshot.phase),
            detail: snapshot.statusSummary,
            payload: codeReviewPayload(snapshot, conversationId: resolvedConversationId),
            phase: codeReviewActivityPhase(snapshot.phase),
            isRunning: snapshot.phase.isActive,
            groupId: "code-review"
        )
        addActivity(activity)
    }

    func codeReviewSnapshots(for conversationId: UUID?) -> [CodeReviewSessionSnapshot] {
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewSnapshotsBySession.values.sorted(by: sortReviewSnapshots)
        }
        let sessionIds = codeReviewSessionIdsByConversation[conversationScope] ?? []
        return sessionIds.compactMap { codeReviewSnapshotsBySession[$0] }
            .sorted(by: sortReviewSnapshots)
    }

    func selectedCodeReviewSessionId(for conversationId: UUID?) -> String? {
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewSnapshotsBySession.values.sorted(by: sortReviewSnapshots).first?.sessionId
        }
        return selectedCodeReviewSessionIdByConversation[conversationScope]
            ?? codeReviewSessionIdsByConversation[conversationScope]?.first
    }

    func setSelectedCodeReviewSessionId(_ sessionId: String?, for conversationId: UUID?) {
        guard let conversationScope = codeReviewConversationScope(conversationId) else { return }
        selectedCodeReviewSessionIdByConversation[conversationScope] = sessionId
    }

    func deleteCodeReviewSession(
        sessionId: String,
        conversationId: UUID?
    ) {
        codeReviewSnapshotsBySession.removeValue(forKey: sessionId)

        if let conversationScope = codeReviewConversationScope(conversationId) {
            codeReviewSessionIdsByConversation[conversationScope]?.removeAll { $0 == sessionId }
            if selectedCodeReviewSessionIdByConversation[conversationScope] == sessionId {
                selectedCodeReviewSessionIdByConversation[conversationScope] =
                    codeReviewSessionIdsByConversation[conversationScope]?.first
            }
        }

        if codeReviewFindingsByConversation.keys.contains(where: { key in
            codeReviewConversationScope(conversationId) == key
        }) {
            let scopedSnapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId)
            let conversationScope = codeReviewConversationScope(conversationId)
            if let conversationScope {
                codeReviewFindingsByConversation[conversationScope] = scopedSnapshot?.findings ?? []
                codeReviewEventsByConversation[conversationScope] = scopedSnapshot?.events ?? []
                codeReviewPhaseByConversation[conversationScope] = scopedSnapshot?.phase ?? .idle
            }
            codeReviewFindings = scopedSnapshot?.findings ?? []
            codeReviewEvents = scopedSnapshot?.events ?? []
            codeReviewPhase = scopedSnapshot?.phase ?? .idle
            codeReviewStage = scopedSnapshot?.stage ?? .idle
        }
    }

    func codeReviewSnapshot(
        sessionId: String?,
        conversationId: UUID?
    ) -> CodeReviewSessionSnapshot? {
        if let sessionId,
           let snapshot = codeReviewSnapshotsBySession[sessionId] {
            guard let conversationId else { return snapshot }
            return snapshot.conversationId == conversationId ? snapshot : nil
        }
        guard let selectedId = selectedCodeReviewSessionId(for: conversationId) else {
            return nil
        }
        return codeReviewSnapshotsBySession[selectedId]
    }

    func codeReviewFindings(for conversationId: UUID?) -> [CodeReviewFinding] {
        if let snapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId) {
            return snapshot.findings
        }
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewFindings
        }
        return codeReviewFindingsByConversation[conversationScope] ?? []
    }

    func codeReviewEvents(for conversationId: UUID?) -> [CodeReviewSessionEvent] {
        if let snapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId) {
            return snapshot.events
        }
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewEvents
        }
        return codeReviewEventsByConversation[conversationScope] ?? []
    }

    func codeReviewPhase(for conversationId: UUID?) -> ReviewSessionPhase {
        if let snapshot = codeReviewSnapshot(sessionId: nil, conversationId: conversationId) {
            return snapshot.phase
        }
        guard let conversationScope = codeReviewConversationScope(conversationId) else {
            return codeReviewPhase
        }
        return codeReviewPhaseByConversation[conversationScope] ?? .idle
    }

    /// Ingests a single code review event as a TaskActivity.
    func ingestCodeReviewEvent(_ event: CodeReviewSessionEvent) {
        let activity = TaskActivity(
            type: "code_review_event",
            title: codeReviewEventTitle(event.type),
            detail: event.detail,
            payload: event.toPayload(),
            phase: .executing,
            isRunning: false,
            groupId: "code-review"
        )
        addActivity(activity)
    }

    // MARK: - Helpers

    private func codeReviewTitle(for phase: ReviewSessionPhase) -> String {
        switch phase {
        case .idle: return "Code Review Idle"
        case .analyzing: return "Analyzing Code..."
        case .fixing: return "Applying Fixes..."
        case .testing: return "Running Tests..."
        case .reReviewing: return "Re-Reviewing..."
        case .completed: return "Code Review Completed"
        case .failed: return "Code Review Failed"
        }
    }

    private func codeReviewActivityPhase(
        _ phase: ReviewSessionPhase
    ) -> ActivityPhase {
        switch phase {
        case .idle: return .thinking
        case .analyzing: return .searching
        case .fixing: return .editing
        case .testing: return .executing
        case .reReviewing: return .searching
        case .completed: return .thinking
        case .failed: return .thinking
        }
    }

    private func codeReviewPayload(
        _ snapshot: CodeReviewSessionSnapshot,
        conversationId: UUID?
    ) -> [String: String] {
        var payload: [String: String] = [
            "phase": snapshot.phase.rawValue,
            "findings_count": String(snapshot.findings.count),
            "open_count": String(snapshot.openFindings.count),
            "round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
        ]
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
        }
        if let error = snapshot.lastError {
            payload["error"] = error
        }
        if let conversationScope = codeReviewConversationScope(conversationId) {
            payload["conversation_id"] = conversationScope
        }
        payload["session_id"] = snapshot.sessionId
        payload["stage"] = snapshot.stage.rawValue
        return payload
    }

    private func codeReviewConversationScope(_ conversationId: UUID?) -> String? {
        conversationId?.uuidString.lowercased()
    }

    private func sortReviewSnapshots(
        _ lhs: CodeReviewSessionSnapshot,
        _ rhs: CodeReviewSessionSnapshot
    ) -> Bool {
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }
        return lhs.sessionId > rhs.sessionId
    }

    private func codeReviewEventTitle(
        _ type: CodeReviewSessionEvent.EventType
    ) -> String {
        switch type {
        case .sessionStarted: return "Review Started"
        case .sessionCompleted: return "Review Completed"
        case .analysisStarted: return "Analysis Started"
        case .analysisCompleted: return "Analysis Completed"
        case .auditStarted: return "Audit Started"
        case .auditCompleted: return "Audit Completed"
        case .findingAdded: return "Finding Added"
        case .findingFixApplied: return "Fix Applied"
        case .findingDismissed: return "Finding Dismissed"
        case .findingCommented: return "Comment Added"
        case .roundStarted: return "Round Started"
        case .roundCompleted: return "Round Completed"
        case .workerSpawned: return "Worker Spawned"
        case .workerCompleted: return "Worker Completed"
        case .testsPassed: return "Tests Passed"
        case .testsFailed: return "Tests Failed"
        case .configUpdated: return "Config Updated"
        case .error: return "Error"
        }
    }
}

// MARK: - ReviewSessionPhase Helpers

extension ReviewSessionPhase {
    var isActive: Bool {
        switch self {
        case .analyzing, .fixing, .testing, .reReviewing:
            return true
        case .idle, .completed, .failed:
            return false
        }
    }
}
