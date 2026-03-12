import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func panelRunConversationId(sourceConversationId: UUID?) -> UUID? {
        conversationId ?? sourceConversationId
    }

    func makePanelReviewSessionState(
        sessionId: String,
        conversationId: UUID?,
        config: SessionConfig
    ) -> CodeReviewSessionState {
        CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: config,
            onStateChange: { [weak self] snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    self?.taskActivityStore.scheduleCodeReviewSnapshotIngest(
                        snapshot,
                        conversationId: self?.conversationId ?? snapshot.conversationId
                    )
                    self?.schedulePanelSessionBinding(snapshot.sessionId)
                }
            }
        )
    }

    func makePanelReviewProvider(
        sessionState: CodeReviewSessionState,
        sessionConfig: SessionConfig
    ) -> CodeReviewMultiSwarmProvider? {
        let config = providerFactoryConfigBuilder()
        return ProviderFactory.codeReviewMultiSwarmProvider(
            config: config,
            executionController: executionController,
            agentProviderId: effectivePanelProviderId,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths,
            sessionState: sessionState,
            initialSessionConfig: sessionConfig
        )
    }

    func activatePanelRunSession(
        sessionId: String,
        conversationId: UUID?
    ) {
        panelSessionId = sessionId
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)
        isRunning = true
        runStartedAt = Date()
        frozenTimerText = nil
        lastError = nil
    }
}
