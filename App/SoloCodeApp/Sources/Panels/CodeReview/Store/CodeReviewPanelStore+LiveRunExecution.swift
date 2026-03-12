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

    func completePanelRun(selectTab targetTab: CodeReviewTab) {
        isRunning = false
        freezeTimer()
        if selectedTab != .chat {
            selectedTab = targetTab
        }
    }

    func failPanelRun(error: String, selectTab targetTab: CodeReviewTab) {
        isRunning = false
        lastError = error
        freezeTimer()
        selectedTab = targetTab
    }

    func runPanelReview(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        sessionState: CodeReviewSessionState,
        sessionId: String,
        conversationId: UUID?,
        selectedTabOnStart: CodeReviewTab,
        selectedTabOnFinish: CodeReviewTab,
        onEvent: @escaping @MainActor (StreamEvent) -> Void,
        onComplete: @escaping @MainActor (CodeReviewSessionSnapshot) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        activatePanelRunSession(sessionId: sessionId, conversationId: conversationId)
        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            onEvent: onEvent,
            onStart: { [weak self] in
                self?.selectedTab = selectedTabOnStart
            },
            onComplete: { [weak self] snapshot in
                guard let self else { return }
                self.completePanelRun(selectTab: selectedTabOnFinish)
                onComplete(snapshot)
            },
            onError: { [weak self] error in
                self?.failPanelRun(error: error, selectTab: selectedTabOnFinish)
                onError(error)
            }
        )
    }
}
