import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func optimizeCurrentPrompt() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let selectedProvider = providerRegistry.selectedProvider else { return }

        // Use lightweight provider (no tools/policy) when available — much faster for prompt optimization.
        // Fall back to full runtime provider if lightweight is not configured or not authenticated.
        let providerToUse: any LLMProvider
        if let providerId = providerRegistry.selectedProviderId,
           let lightweight = ProviderFactory.lightweightProvider(
               providerId: providerId,
               config: providerFactoryConfig(),
               executionController: executionController
           ),
           lightweight.isAuthenticated() {
            providerToUse = lightweight
        } else if let resolved = resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: false,
            forcePlanInline: false
        ) {
            providerToUse = resolved
        } else {
            providerToUse = selectedProvider
        }

        isOptimizingPrompt = true
        promptOptimizerTask?.cancel()
        promptOptimizerTask = Task {
            defer { isOptimizingPrompt = false }
            do {
                let ctx = WorkspaceContext.minimal()
                let optimized = try await PromptOptimizerService.optimize(
                    prompt: prompt,
                    using: providerToUse,
                    context: ctx
                )
                guard !Task.isCancelled else { return }
                optimizedPromptResult = optimized
                showPromptOptimizerPopup = true
            } catch {
                guard !Task.isCancelled else { return }
                appendTechnicalErrorMessage("[Prompt Optimizer] \(error.localizedDescription)", in: conversationId)
            }
        }
    }

    internal func sendMessage() {
        let parsedInput = parsePlanCommandInput(inputText)
        let text = parsedInput.llmPromptInput
        let displayedInput = parsedInput.displayedInput
        let forcePlanInline = parsedInput.forcePlanInline
        if forcePlanInline {
            // `/plan` should force the planning flow and open the dedicated panel.
            planToggleEnabled = true
            if !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        }
        guard !text.isEmpty || !attachedComposerAttachments.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Error] No conversation selected. Create or select a thread and try again.",
                in: nil
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Error] No provider selected. Configure a provider in Settings.",
                in: targetConversationId
            )
            return
        }
        hasJustCompletedTask = false

        // Check rate limit before proceeding — show alert popup if at 100%
        if let rateLimitMsg = providerUsageStore.rateLimitAlertMessage(
            for: providerRegistry.selectedProviderId)
        {
            rateLimitAlertText = rateLimitMsg
            showRateLimitAlert = true
            return
        }

        // Opening the plan panel should not automatically activate planning.
        let shouldRunPlanInline = resolveShouldRunPlanInline(
            forcePlanInline: forcePlanInline,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        )
        let isPlanModeRequested = (coderMode == .plan || shouldRunPlanInline)
        func resetPlanFlowAfterPreflightFailureIfNeeded() {
            guard shouldResetPlanFlowAfterPreflightFailure(
                isPlanModeRequested: isPlanModeRequested,
                phase: planFlowPhase
            ) else {
                return
            }
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }
        if isPlanModeRequested {
            // Guard against launching a new plan flow while one is already in progress
            switch planFlowPhase {
            case .analyzing, .questioning, .generating, .building:
                appendTechnicalErrorMessage(
                    "[Plan] A plan flow is already in progress. Please wait for it to finish or interrupt it first.",
                    in: targetConversationId
                )
                return
            default:
                break
            }
            planFlowPhase = .analyzing
            planningState = .idle
            planAnalysisContext = ""
            planUserRequest = String(text.prefix(16_000))
            planClarificationAnswers = ""
            planClarificationCycles = 0
            clearPlanStreamingState()
            planShouldRunInline = shouldRunPlanInline
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        } else if planFlowPhase != .building {
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        }

        // 1. Resolve the runtime provider
        guard
            let runtimeProvider = resolveRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline
            )
        else {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Error] Unable to resolve runtime provider for this mode.",
                in: targetConversationId
            )
            return
        }

        let selectedProviderAuthenticated = runtimeProvider.isAuthenticated()
        let preferredFallbackProvider = preferredRealProvider()
        var effectiveRuntimeProvider: any LLMProvider = runtimeProvider
        if shouldFallbackToPreferredProvider(
            selectedProviderIsAuthenticated: selectedProviderAuthenticated,
            hasPreferredAuthenticatedFallback: preferredFallbackProvider != nil
        ),
            let fallbackProvider = preferredFallbackProvider
        {
            effectiveRuntimeProvider = fallbackProvider
            appendTechnicalErrorMessage(
                "[Provider] \(runtimeProvider.displayName) not authenticated. Using fallback: \(fallbackProvider.displayName).",
                in: targetConversationId
            )
        } else if !selectedProviderAuthenticated {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Error] Provider \(providerName) not authenticated and no fallback available. Open Settings and authenticate an execution-capable provider.",
                in: targetConversationId
            )
            return
        }

        // 2. Build workspace context & checkpoint
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            resetPlanFlowAfterPreflightFailureIfNeeded()
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // 3. Prepare messages in chat store
        let turnId = UUID()
        let attachmentBundle = buildAttachmentBundle(
            attachments: attachedComposerAttachments,
            workspaceURL: ctx.workspacePath,
            turnId: turnId,
            capabilities: effectiveRuntimeProvider.attachmentCapabilities
        )
        let imagePathsToStore = attachmentBundle.chat
            .filter { $0.kind == .image }
            .map(\.localPath)
        inputText = ""
        let userVisibleText = displayedInput
        let contentToStore =
            userVisibleText.isEmpty ? (attachmentBundle.chat.isEmpty ? "" : "[Attached files]") : userVisibleText
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore,
                attachments: attachmentBundle.chat.isEmpty ? nil : attachmentBundle.chat
            ),
            to: targetConversationId
        )
        let standardAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: standardAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: targetConversationId
        )
        startToolTraceTurn(
            conversationId: targetConversationId,
            assistantMessageId: standardAssistantMessageId,
            providerId: effectiveRuntimeProvider.id
        )
        if let conv = chatStore.conversation(for: targetConversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId, folderPath: conv.contextFolderPath, conversationId: conv.id)
        }
        chatStore.beginTask(conversationId: targetConversationId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: targetConversationId
        ) {
            clearTaskActivityPipeline()
        }
        // Preserve manual todos across turns; for a new standard turn reset all agent todos,
        // including stale canonical plan tasks from previous plans/conversations.
        // During an active plan build, keep canonical todos so the build's todo
        // tracking isn't wiped by a concurrent user message.
        let hasActivePlanBuildTask = activeBuildAgentConversationId.map { chatStore.isTaskActive(for: $0) } ?? false
        let shouldClearPlanCanonicalTodos = shouldClearPlanCanonicalTodosOnNewTurn(
            phase: planFlowPhase,
            hasActivePlanBuildTask: hasActivePlanBuildTask
        )
        todoStore.clearAgentTodos(includePlanCanonical: shouldClearPlanCanonicalTodos)
        scheduleFallbackTurnStartEvent(
            conversationId: targetConversationId,
            providerId: effectiveRuntimeProvider.id
        )
        swarmProgressStore.clear()

        let attachmentsToSend = attachmentBundle.llm.isEmpty ? nil : attachmentBundle.llm
        attachedComposerAttachments = []

        // 4. Build the prompt with mode-specific instructions
        let basePrompt = buildPrompt(userText: text, shouldRunPlanInline: shouldRunPlanInline)
        let prompt = attachmentBundle.fallbackPreamble.isEmpty
            ? basePrompt
            : "\(attachmentBundle.fallbackPreamble)\n\n\(basePrompt)"

        // 5. Execute async stream
        let isPlanMultiTurnFlow = (coderMode == .plan || shouldRunPlanInline) && planFlowPhase == .analyzing
        launchRunTask(for: targetConversationId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                if isPlanMultiTurnFlow {
                    // Multi-turn forced sequential plan flow
                    try await runMultiTurnPlanFlow(
                        provider: effectiveRuntimeProvider,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        conversationId: targetConversationId,
                        shouldRunPlanInline: shouldRunPlanInline
                    )
                    // Safety net: if the flow returned without advancing to a terminal
                    // state (e.g., early return from a conversation-ID guard), reset the
                    // phase so the user isn't permanently stuck.
                    // Exception: .questioning + .awaitingClarification is a legitimate
                    // pause — the user needs to answer before the flow continues.
                    await MainActor.run {
                        guard shouldMutatePlanState(
                            targetConversationId: targetConversationId,
                            currentConversationId: self.conversationId
                        ) else { return }
                        let isPausedForClarification: Bool = {
                            if case .awaitingClarification = planningState { return true }
                            return false
                        }()
                        switch planFlowPhase {
                        case .analyzing, .generating:
                            NSLog("[PlanFlow] Safety reset: planFlowPhase was still %@ after runMultiTurnPlanFlow returned", String(describing: planFlowPhase))
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        case .questioning where !isPausedForClarification:
                            NSLog("[PlanFlow] Safety reset: planFlowPhase was .questioning without awaitingClarification")
                            planFlowPhase = .idle
                            planningState = .idle
                            clearPlanStreamingState()
                        default:
                            break
                        }
                    }
                } else {
                    // Standard single-stream flow (non-plan modes + plan build)
                    let streamResult = try await flowCoordinator.runStream(
                        provider: effectiveRuntimeProvider,
                        prompt: prompt,
                        context: ctx,
                        attachments: attachmentsToSend,
                        onText: { content in
                            applyStreamingUpdate(
                                content: content,
                                conversationId: targetConversationId
                            )
                        },
                        onRaw: { t, p, pid in
                            handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: targetConversationId)
                        },
                        onError: { content in
                            Task { @MainActor in
                                chatStore.updateLastAssistantMessage(content: content, in: targetConversationId)
                            }
                        },
                        onSignal: nil
                    )

                    let finalizedResult = try await continueIfPrematureStub(
                        initial: streamResult,
                        provider: effectiveRuntimeProvider,
                        originalPrompt: prompt,
                        context: ctx,
                        conversationId: targetConversationId,
                        hideContentDuringPlanDiscovery: false
                    )

                    // 6. Handle stream completion (plan options)
                    await handleStreamResult(
                        conversationId: targetConversationId,
                        fullText: finalizedResult, shouldRunPlanInline: shouldRunPlanInline,
                        ctx: ctx, attachmentsToSend: attachmentsToSend, prompt: prompt
                    )
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId)
                    await MainActor.run {
                        applyFlowCoordinatorState(for: targetConversationId) { $0.fail() }
                    }
                }
                // C1 fix: Reset plan flow phase on error to prevent permanent stuck state.
                // Also reset if conversation changed but phase is stuck in a progress state.
                await MainActor.run {
                    guard shouldMutatePlanState(
                        targetConversationId: targetConversationId,
                        currentConversationId: self.conversationId
                    ) else { return }
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        }
    }

    // MARK: - Multi-Turn Plan Flow

}
