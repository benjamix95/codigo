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

        guard let selectedProviderId = providerRegistry.selectedProviderId else {
            appendTechnicalErrorMessage(
                "[Plan] No provider selected.",
                in: targetConversationId
            )
            return
        }
        guard isPlanBuildExecutionCapableProvider(selectedProviderId, registry: providerRegistry) else {
            appendTechnicalErrorMessage(
                "[Plan] Provider not execution-capable (\(selectedProviderId)).",
                in: targetConversationId
            )
            return
        }
        guard let effectiveProvider = providerRegistry.provider(for: selectedProviderId) else {
            appendTechnicalErrorMessage(
                "[Plan] Provider not available (\(selectedProviderId)).",
                in: targetConversationId
            )
            return
        }
        guard effectiveProvider.isAuthenticated() else {
            appendTechnicalErrorMessage(
                "[Plan] Provider not authenticated (\(effectiveProvider.displayName)). Authenticate this provider in Settings.",
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
            snapshotSubagentCardsAndEndTask(
                conversationId: targetConversationId,
                outcome: traceOutcome
            )
        }
    }

    /// After clarification answers, re-analyze and decide: ask more questions or proceed to plan generation.
    internal func runPostClarificationFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        let reanalysisStartContext = await MainActor.run { () -> (shouldStart: Bool, questionEpochBaseline: Int) in
            guard self.conversationId == conversationId else {
                return (
                    false,
                    planQuestionToolEpoch(for: conversationId)
                )
            }
            _ = planRuntimeAction(
                "plan_prepare_post_clarification_analysis_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline
            )
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
            return (
                true,
                planQuestionToolEpoch(for: conversationId)
            )
        }
        let shouldStartReanalysis = reanalysisStartContext.shouldStart
        let questionToolEpochBaseline = reanalysisStartContext.questionEpochBaseline
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
        let didReceiveToolDrivenQuestionnaire = await MainActor.run { () -> Bool in
            planQuestionToolEpoch(for: conversationId) > questionToolEpochBaseline
        }
        if didReceiveToolDrivenQuestionnaire {
            return
        }

        let runtimeSnapshot = planRuntimeAction(
            "plan_apply_post_clarification_analysis_result",
            text: reAnalysisText,
            shouldRunInline: shouldRunPlanInline
        )

        if let runtimeSnapshot,
           runtimeSnapshot.plan?.planningStateKind == .awaitingClarification,
           runtimeSnapshot.plan?.clarificationQuestions != nil
        {
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
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
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return
        }

        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

}
