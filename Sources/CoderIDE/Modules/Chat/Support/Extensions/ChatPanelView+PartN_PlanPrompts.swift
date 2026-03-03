import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func continuePlanFlowPhase3() {
        guard let targetConversationId = conversationId else {
            NSLog("[PlanFlow] continuePlanFlowPhase3 aborted: conversationId is nil")
            return
        }
        // Don't silently block if a lingering task is still marked active — force-end it.
        // The user explicitly submitted clarification answers, so the flow must continue.
        if isLoadingForCurrentConversation {
            NSLog("[PlanFlow] continuePlanFlowPhase3: isLoading=true for %@, force-ending lingering task", targetConversationId.uuidString)
            snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        }

        let effectiveProvider: any LLMProvider
        if let selected = providerRegistry.selectedProvider {
            if selected.isAuthenticated() {
                effectiveProvider = selected
            } else if let fallback = preferredRealProvider() {
                effectiveProvider = fallback
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] No authenticated provider available.",
                    in: targetConversationId
                )
                return
            }
        } else {
            appendTechnicalErrorMessage(
                "[Plan] No provider selected.",
                in: targetConversationId
            )
            return
        }

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        // Create a checkpoint before the post-clarification flow so we can
        // rewind if the re-analysis or plan generation causes unwanted changes.
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Checkpoint error: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // Recompute inline flag fresh instead of relying on the stale captured
        // planShouldRunInline — the user may have toggled modes since the original request.
        let currentShouldRunInline = resolveShouldRunPlanInline(
            forcePlanInline: false,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        ) || planShouldRunInline // preserve original intent as fallback

        chatStore.beginTask(conversationId: targetConversationId)
        launchRunTask(for: targetConversationId) {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                try await runPostClarificationFlow(
                    provider: effectiveProvider,
                    ctx: ctx,
                    conversationId: targetConversationId,
                    shouldRunPlanInline: currentShouldRunInline
                )
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
                        content: userFacingStreamError(error), in: targetConversationId
                    )
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

    /// After clarification answers, re-analyze and decide: ask more questions or proceed to plan generation.
    internal func runPostClarificationFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        let shouldStartReanalysis = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .analyzing
            clearPlanStreamingState()
            let reanalysisAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: reanalysisAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: reanalysisAssistantMessageId,
                providerId: provider.id
            )
            return true
        }
        guard shouldStartReanalysis else {
            // Conversation changed before post-clarification reanalysis.
            return
        }

        let reAnalysisPrompt = buildPostClarificationAnalysisPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let reAnalysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: reAnalysisPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                updatePlanStreamingContent(content, conversationId: conversationId)
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                Task { @MainActor in
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let reAnalysisText = reAnalysisResult.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the LLM produced more questions or is ready for plan generation
        let classification = PlanOutputClassifier.classify(
            fullText: reAnalysisText,
            current: .questioning,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        let allowFollowUpClarification = shouldAllowFollowUpClarification(
            userRequest: planUserRequest,
            clarificationCycles: planClarificationCycles
        )

        if allowFollowUpClarification,
           classification.isConfident,
           case .awaitingClarification(let q) = classification.planningState
        {
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                planClarificationCycles += 1
                let followUp = "\n\n--- Follow-up analysis ---\n\(reAnalysisText)"
                planAnalysisContext = String((planAnalysisContext + followUp).suffix(32_000))
                planFlowPhase = .questioning
                planningState = .awaitingClarification(questions: q)
                updatePlanStreamingContent(reAnalysisText, conversationId: conversationId)
                chatStore.updateLastAssistantMessage(
                    content: "Questions ready — answer in the plan panel.",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
            // STOP — will re-enter via submitPlanClarificationAnswers → continuePlanFlowPhase3
            return
        }

        let shouldProceedPhase3 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            let postClarification = "\n\n--- Post-clarification analysis ---\n\(reAnalysisText)"
            planAnalysisContext = String((planAnalysisContext + postClarification).suffix(32_000))
            chatStore.updateLastAssistantMessage(
                content: "Questions answered. Generating definitive plan...",
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearPlanStreamingState()
            return true
        }
        guard shouldProceedPhase3 else {
            // Conversation changed before Phase 3.
            return
        }

        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

    internal func continueIfPrematureStub(
        initial: String,
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> String {
        var combinedText = initial
        let maxAutoContinuationRounds = 3
        var round = 0

        while shouldAutoContinueStub(combinedText),
              round < maxAutoContinuationRounds {
            round += 1
            let continuationPrompt = """
            Immediately continue your previous response and complete the task to a concrete outcome.
            Execute needed steps autonomously (analyze, act, verify, fix if needed) and do not stop at intentions.

            Original request:
            \(originalPrompt)

            Text already sent:
            \(combinedText)
            """

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
                        : combined
                    applyStreamingUpdate(
                        content: displayContent,
                        conversationId: conversationId
                    )
                },
                onRaw: { t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { content in
                    DispatchQueue.main.async {
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp
        }

        return combinedText
    }

    internal func shouldAutoContinueStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let low = trimmed.lowercased()
        let stubSignals = [
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "first, i'll",
            "first i will",
            "let me start",
            "let me begin",
            "let me check",
            "i can continue",
            "would you like me to",
            "if you want i can",
            "next i'll",
            "next i will",
        ]
        if stubSignals.contains(where: { low.contains($0) }) {
            return true
        }
        if low.hasSuffix("...") || low.hasSuffix(":") {
            return true
        }
        return false
    }

    // MARK: - Resolve Runtime Provider

    internal func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool
    ) -> (any LLMProvider)? {
        // Plan/Swarm use real selected providers, without virtual providers.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return selectedProvider
        }
        // Code Review Multi-Swarm: build dedicated multi-swarm provider
        if coderMode == .codeReviewMultiSwarm {
            let cfg = providerFactoryConfig()
            if let multiSwarm = ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: runtimeWorkspacePaths
            ) {
                return multiSwarm
            }
            // Factory returned nil — surface the error in chat so the user knows.
            // Common cause: API key missing for the selected backend.
            let analysisBackend = cfg.codeReviewAnalysisBackend
            let executionBackend = cfg.codeReviewExecutionBackend
            let msg = "[Code Review] Failed to create multi-swarm provider (analysis: \(analysisBackend), execution: \(executionBackend)). Check your API keys in Settings."
            print("[CodeReview] WARNING: \(msg)")
            appendTechnicalErrorMessage(msg, in: conversationId)
            return nil
        }
        if multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            // Check if all accounts are exhausted
            if case .allExhausted(let reason) = cliAccountRouter.currentAvailability(
                provider: kind)
            {
                appendTechnicalErrorMessage(
                    "[Multi-account \(kind.displayName): \(reason). Configure accounts or reset limits in Settings.]",
                    in: conversationId)
                return nil
            }
            let availability = cliAccountRouter.currentAvailability(provider: kind)
            if case .allExhausted = availability {
                return selectedProvider
            }
            return CLIMultiAccountProviderAdapter(
                providerKind: kind,
                id: selectedProviderId,
                displayName: selectedProvider.displayName,
                router: cliAccountRouter,
                accountsStore: cliAccountsStore,
                makeProvider: { _, env in
                    let cfg = providerFactoryConfig()
                    let subagentFactory = ProviderFactory.subagentProviderFactory(
                        config: cfg,
                        executionController: executionController,
                        codebaseIndex: workspaceStore.codebaseIndex,
                        workspacePaths: runtimeWorkspacePaths
                    )
                    switch kind {
                    case .codex:
                        return ProviderFactory.codexProvider(
                            config: cfg, executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .claude:
                        return ProviderFactory.claudeProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    case .gemini:
                        return ProviderFactory.geminiProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: runtimeWorkspacePaths,
                            environmentOverride: env,
                            subagentProviderFactory: subagentFactory)
                    }
                }
            )
        }
        return selectedProvider
    }

    // MARK: - Clarification Heuristics

    internal func userExplicitlyWantsClarifications(_ userRequest: String) -> Bool {
        let normalized = userRequest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return normalized.range(
            of: #"(chiedi|fammi|poni).{0,20}(domande|chiarimenti)|ask.{0,20}(questions|clarifications)"#,
            options: .regularExpression
        ) != nil
    }

    internal func shouldAskPlanClarifications(analysisText: String, userRequest: String) -> Bool {
        if userExplicitlyWantsClarifications(userRequest) {
            return true
        }

        let normalized = "\(analysisText)\n\(userRequest)".lowercased()
        let blockingPatterns: [String] = [
            #"\b(blocked|cannot proceed|can't proceed|impossible to proceed)\b"#,
            #"\b(missing requirement|missing decision|decision needed|unknown requirement)\b"#,
            #"\b(ambiguous|unclear|not enough information|insufficient information)\b"#,
            #"\b(conflicting requirement|conflicting constraints|trade[- ]off not specified)\b"#,
            #"\b(need clarification|requires clarification|clarification required)\b"#,
        ]
        var hits = 0
        for pattern in blockingPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                hits += 1
            }
        }
        return hits >= 3
    }

    internal func shouldAllowFollowUpClarification(
        userRequest: String,
        clarificationCycles: Int
    ) -> Bool {
        // Keep a single clarification round by default to avoid loops.
        guard clarificationCycles < 1 else {
            return false
        }
        return userExplicitlyWantsClarifications(userRequest)
    }

    // MARK: - Build Prompt

}
