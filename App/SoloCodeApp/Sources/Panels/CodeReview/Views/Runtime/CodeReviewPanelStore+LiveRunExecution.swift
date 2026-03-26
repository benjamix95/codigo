import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func consumePendingLaunchRequestIfNeeded() async {
        guard let request = ReviewPanelLaunchRequestStore.shared.consume(conversationId: conversationId) else {
            return
        }
        scopeTarget = request.scope
        selectedModes = request.modes
        reviewScanDepth = request.reviewScanDepth
        selectTab(.findings)
        await startReview(
            scope: request.scope,
            modes: request.modes,
            promptOverride: request.promptOverride,
            invocationLabel: request.invocationLabel
        )
    }

    func processNextPendingCodeReviewLaunchIfIdle() async {
        guard !isRunning else { return }
        await consumePendingLaunchRequestIfNeeded()
    }

    func startReview(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>,
        promptOverride: String? = nil,
        invocationLabel: String? = nil
    ) async {
        var codebasePromptPaths: [String]?
        if case .codebase = scope {
            let split = await gatherCodebaseIndexedPathsForRun(depth: reviewScanDepth)
            pendingCodebaseWorkspaceIncludedPaths = split.workspaceIncludedPaths.isEmpty
                ? nil
                : split.workspaceIncludedPaths
            codebasePromptPaths = split.promptPaths
        } else {
            pendingCodebaseWorkspaceIncludedPaths = nil
            codebasePromptPaths = nil
        }

        let resolvedPrompt: String
        if let promptOverride {
            resolvedPrompt = promptOverride
        } else {
            resolvedPrompt = await buildPrompt(
                scope: scope,
                modes: modes,
                precomputedCodebasePromptPaths: codebasePromptPaths
            )
        }
        let resolvedLabel = invocationLabel ?? reviewInvocationLabel(scope: scope, modes: modes)

        guard !isRunning else {
            ReviewPanelLaunchRequestStore.shared.enqueue(
                ReviewPanelLaunchRequest(
                    conversationId: conversationId,
                    scope: scope,
                    modes: modes,
                    reviewScanDepth: reviewScanDepth,
                    promptOverride: resolvedPrompt,
                    invocationLabel: resolvedLabel
                )
            )
            return
        }

        scopeTarget = scope
        selectedModes = modes
        reviewReportExportNotice = nil
        selectTab(.findings)

        guard let plan = planPanelReviewLaunch() else {
            applyUnavailableRunError(
                "Failed to plan review session",
                targetTab: .findings
            )
            await processNextPendingCodeReviewLaunchIfIdle()
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
            pendingCodebaseWorkspaceIncludedPaths = nil
            applyUnavailableRunError(
                "Failed to create review provider",
                targetTab: .findings
            )
            await processNextPendingCodeReviewLaunchIfIdle()
            return
        }

        let prompt = resolvedPrompt
        let context = buildWorkspaceContext()
        let reportScope = scopeTarget
        let reportDepth = reviewScanDepth
        #if DEBUG
        ReviewPanelDebugNDJSON.emit(
            hypothesisId: "H_run_start",
            location: "CodeReviewPanelStore+LiveRunExecution.startReview",
            message: "panel_review_launch",
            data: [
                "scanDepth": reviewScanDepth.rawValue,
                "sessionId": sessionId,
                "modeLabels": modes.map(\.rawValue).sorted().joined(separator: ","),
            ]
        )
        #endif
        runPanelReview(
            provider: provider,
            prompt: prompt,
            context: context,
            sessionState: sessionState,
            sessionId: sessionId,
            conversationId: conversationId,
            selectedTabOnStart: .findings,
            selectedTabOnFinish: .findings,
            onEvent: { [weak self] event in
                self?.handlePanelReviewStreamEvent(event)
            },
            onComplete: { [weak self] snapshot in
                guard let self else { return }
                Task { await self.maybeExportReviewReportArtifacts(
                    snapshot: snapshot,
                    scope: reportScope,
                    depth: reportDepth
                ) }
            },
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
                    let hotPhases: Set<ReviewSessionPhase> = [
                        .analyzing, .fixing, .testing, .reReviewing,
                    ]
                    let delayNs: UInt64 = hotPhases.contains(snapshot.phase) ? 0 : 8_000_000
                    self?.taskActivityStore.scheduleCodeReviewSnapshotIngest(
                        snapshot,
                        conversationId: self?.conversationId ?? snapshot.conversationId,
                        uiCoalesceDelayNanoseconds: delayNs
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
        if !applyPanelIntent("bind_panel_session", value: sessionId),
           !ReviewCoreBridge.isEnabled {
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
            Task { @MainActor [weak self] in
                await self?.processNextPendingCodeReviewLaunchIfIdle()
            }
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
                Task { @MainActor [weak self] in
                    await self?.processNextPendingCodeReviewLaunchIfIdle()
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
        pendingCodebaseWorkspaceIncludedPaths = nil
        return response?.outcome
    }

    func applyUnavailableRunError(_ message: String, targetTab: CodeReviewTab) {
        pendingCodebaseWorkspaceIncludedPaths = nil
        isRunning = false
        lastError = message
        frozenTimerText = nil
        selectTab(targetTab)
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
