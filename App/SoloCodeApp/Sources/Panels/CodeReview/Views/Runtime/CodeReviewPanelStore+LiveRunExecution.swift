import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func consumePendingLaunchRequestIfNeeded() async {
        guard let request = ReviewPanelLaunchRequestStore.shared.consume(conversationId: conversationId) else {
            return
        }
        scopeTarget = request.scope
        selectedModes = request.modes
        selectTab(.findings)
        await startReview(
            scope: request.scope,
            modes: request.modes,
            promptOverride: request.promptOverride,
            invocationLabel: request.invocationLabel
        )
    }

    func startReview(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>,
        promptOverride: String? = nil,
        invocationLabel: String? = nil
    ) async {
        guard !isRunning else { return }

        lastError = nil
        isRunning = true
        runStartedAt = Date()
        frozenTimerText = nil
        scopeTarget = scope
        selectedModes = modes
        selectTab(.findings)

        guard let plan = planPanelReviewLaunch() else {
            isRunning = false
            lastError = "Failed to plan review session"
            freezeTimer()
            return
        }
        let sessionId = plan.sessionId
        let sessionConfig = plan.config
        let sessionState = makePanelReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: sessionConfig
        )

        await ReviewSessionRegistry.shared.register(sessionState)

        guard let provider = makePanelReviewProvider(
            sessionState: sessionState,
            sessionConfig: sessionConfig
        ) else {
            isRunning = false
            lastError = "Failed to create review provider"
            freezeTimer()
            return
        }

        let prompt = promptOverride ?? buildPrompt(scope: scope, modes: modes)
        let context = buildWorkspaceContext()
        runPanelReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            sessionId: sessionId,
            conversationId: conversationId,
            selectedTabOnStart: .findings,
            selectedTabOnFinish: .findings,
            onEvent: { _ in },
            onComplete: { _ in },
            onError: { _ in }
        )
    }

    func cancelReview() {
        coordinator.cancelReview()
        completePanelRun(selectTab: .findings)
    }

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

    func bindPanelRunSession(
        sessionId: String,
        conversationId: UUID?
    ) {
        if !applyPanelIntent("bind_panel_session", value: sessionId) {
            panelSessionId = sessionId
        }
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)
    }

    func activatePanelRunSession(
        sessionId: String,
        conversationId: UUID?,
        selectedTabOnStart: CodeReviewTab = .findings,
        startedAt: Date = Date()
    ) {
        bindPanelRunSession(sessionId: sessionId, conversationId: conversationId)
        _ = applyPanelRunStart(
            selectedTabOnStart: selectedTabOnStart,
            startedAt: startedAt
        )
    }

    func completePanelRun(selectTab targetTab: CodeReviewTab) {
        _ = applyPanelRunFinish(
            selectedTabOnFinish: targetTab,
            finishedAt: Date(),
            snapshot: nil,
            error: nil,
            wasCancelled: false
        )
    }

    func failPanelRun(error: String, selectTab targetTab: CodeReviewTab) {
        _ = applyPanelRunFinish(
            selectedTabOnFinish: targetTab,
            finishedAt: Date(),
            snapshot: nil,
            error: error,
            wasCancelled: false
        )
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
        bindPanelRunSession(sessionId: sessionId, conversationId: conversationId)
        guard applyPanelRunStart(
            selectedTabOnStart: selectedTabOnStart,
            startedAt: Date()
        ) else {
            let message = ReviewPanelStateRustAdapter.runtimeUnavailableMessage
            applyUnavailableRunError(message, targetTab: selectedTabOnFinish)
            onError(message)
            return
        }
        coordinator.runReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            onEvent: onEvent,
            onStart: { },
            onFinish: { [weak self] result in
                guard let self else { return }
                let outcome = self.applyPanelRunFinish(
                    selectedTabOnFinish: selectedTabOnFinish,
                    finishedAt: Date(),
                    snapshot: result.snapshot,
                    error: result.error,
                    wasCancelled: result.wasCancelled
                )
                switch outcome?.status {
                case "completed":
                    onComplete(result.snapshot)
                case "failed":
                    onError(outcome?.message ?? ReviewPanelStateRustAdapter.runtimeUnavailableMessage)
                default:
                    break
                }
            }
        )
    }
}

private extension CodeReviewPanelStore {
    func applyPanelRunStart(
        selectedTabOnStart: CodeReviewTab,
        startedAt: Date
    ) -> Bool {
        let response: ReviewPanelRuntimeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_run_start",
            request: ReviewPanelRunStartRequest(
                state: makeRuntimeStateSnapshot(),
                selectedTabOnStart: selectedTabOnStart.rawValue,
                startedAt: startedAt
            )
        )
        guard response?.error == nil, let state = response?.state else {
            return false
        }
        applyRuntimeState(state)
        return true
    }

    func applyPanelRunFinish(
        selectedTabOnFinish: CodeReviewTab,
        finishedAt: Date,
        snapshot: CodeReviewSessionSnapshot?,
        error: String?,
        wasCancelled: Bool
    ) -> ReviewPanelRuntimeOutcome? {
        let response: ReviewPanelRuntimeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_run_finish",
            request: ReviewPanelRunFinishRequest(
                state: makeRuntimeStateSnapshot(),
                selectedTabOnFinish: selectedTabOnFinish.rawValue,
                finishedAt: finishedAt,
                snapshotPhase: snapshot?.phase.rawValue,
                snapshotLastError: snapshot?.lastError,
                errorMessage: error,
                wasCancelled: wasCancelled
            )
        )
        guard response?.error == nil, let state = response?.state else {
            let message = error ?? ReviewPanelStateRustAdapter.runtimeUnavailableMessage
            applyUnavailableRunError(message, targetTab: selectedTabOnFinish)
            return ReviewPanelRuntimeOutcome(status: "failed", message: message)
        }
        applyRuntimeState(state)
        return response?.outcome
    }

    func applyUnavailableRunError(_ message: String, targetTab: CodeReviewTab) {
        isRunning = false
        lastError = message
        frozenTimerText = nil
        selectedTab = targetTab
    }
}

private struct ReviewPanelRunStartRequest: Encodable {
    let schemaVersion: Int = 1
    let state: ReviewPanelRuntimeStateSnapshot
    let selectedTabOnStart: String
    let startedAt: Date
}

private struct ReviewPanelRunFinishRequest: Encodable {
    let schemaVersion: Int = 1
    let state: ReviewPanelRuntimeStateSnapshot
    let selectedTabOnFinish: String
    let finishedAt: Date
    let snapshotPhase: String?
    let snapshotLastError: String?
    let errorMessage: String?
    let wasCancelled: Bool
}
