import CoderEngine
import Foundation

extension SoloCodeApp {
    @MainActor
    func makeCommandReviewSessionState(
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionState {
        CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: config,
            onStateChange: { snapshot in
                Task { @MainActor in
                    MCPSharedState.writeCodeReviewSnapshot(snapshot)
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    DispatchQueue.main.async { [taskActivityStore = self.taskActivityStore] in
                        taskActivityStore.scheduleCodeReviewSnapshotIngest(snapshot, conversationId: conversationId)
                    }
                }
            }
        )
    }

    @MainActor
    func codeReviewCommandContext() -> WorkspaceContext {
        CodeReviewCommandRuntimeHooks.workspaceContext(for: self)
    }

    @MainActor
    func resolveCodeReviewSnapshot(
        sessionId: String,
        conversationId: UUID?
    ) -> CodeReviewSessionSnapshot? {
        let snapshot = taskActivityStore.codeReviewSnapshot(sessionId: sessionId, conversationId: conversationId)
            ?? MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId)
        guard let snapshot else { return nil }
        guard conversationId == nil || snapshot.conversationId == conversationId else {
            return nil
        }
        return snapshot
    }

    @MainActor
    func makeTargetedFixSessionId(sourceSessionId: String) -> String {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        let candidate = "\(sourceSessionId)-fix-\(suffix)"
        if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(candidate) {
            return sanitized
        }
        return UUID().uuidString.lowercased()
    }

    @MainActor
    func markFindingFixApplied(
        sessionId: String,
        conversationId: UUID?,
        findingId: String
    ) async -> Bool {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            let succeeded = await liveState.applyFix(findingId: findingId)
            if succeeded {
                await persistLiveReviewState(liveState, conversationId: conversationId)
            }
            return succeeded
        }

        let result = await persistReviewSnapshotMutation(sessionId: sessionId, conversationId: conversationId) { snapshot in
            guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
                snapshot,
                action: "apply_fix",
                payload: ["finding_id": findingId]
            ),
            !mutation.isError,
            let canonical = mutation.snapshot else {
                return nil
            }
            return canonical
        }
        return result.success
    }
}
