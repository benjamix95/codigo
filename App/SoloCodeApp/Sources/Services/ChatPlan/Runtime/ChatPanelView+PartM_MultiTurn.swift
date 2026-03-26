import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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

        while round < maxAutoContinuationRounds {
            let runtimeSnapshot = flowCoordinator.prepareDirectStreamContinuation(
                originalPrompt: originalPrompt,
                currentText: combinedText
            )
            guard let continuationPrompt = runtimeSnapshot?.output?.followUpPrompt else {
                break
            }
            round += 1
            if let runtimeSnapshot {
                flowCoordinator.setDirectRuntimeSnapshot(runtimeSnapshot)
            }

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
                    let shouldSanitize = isPlanBuildContext(
                        conversationId: conversationId,
                        phase: planFlowPhase,
                        activeBuildPlanConversationId: activeBuildPlanConversationId,
                        activeBuildAgentConversationId: activeBuildAgentConversationId
                    )
                    let sanitizedContent = shouldSanitize
                        ? stripPlanCheckboxes(displayContent)
                        : displayContent
                    appendPlanStreamingContent(
                        sanitizedContent,
                        conversationId: conversationId
                    )
                    if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
                    applyLegacyStreamSnapshot(
                        content: sanitizedContent,
                        conversationId: conversationId,
                        providerId: resolvedTurnProviderId(for: conversationId)
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
}

extension ChatPanelView {
    internal func runMultiTurnPlanFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool,
        fullTurnPromptForScreeningFallback: String,
        skipScreening: Bool = false
    ) async throws -> MultiTurnPlanFlowOutcome {
        // ========================
        // PHASE 0: Screening (internal; chat shows only neutral status)
        // ========================
        if !skipScreening {
            let screeningPrompt = await MainActor.run { () -> String in
                guard self.conversationId == conversationId else { return "" }
                return buildPhase0ScreeningPrompt(
                    userRequest: planUserRequest,
                    planIntentConversationId: conversationId
                )
            }
            guard !screeningPrompt.isEmpty else {
                await MainActor.run {
                    cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
                }
                return .completed
            }
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                chatStore.updateLastAssistantMessage(
                    content: "Starting codebase analysis...",
                    in: conversationId
                )
            }
            let screeningResult = try await flowCoordinator.runStream(
                provider: provider,
                prompt: screeningPrompt,
                context: ctx,
                attachments: attachmentsToSend,
                onText: { _ in },
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

            let screeningText = screeningResult.trimmingCharacters(in: .whitespacesAndNewlines)
            let screeningSnapshot = await MainActor.run { () -> MainChatRuntimeSnapshotBridge? in
                guard self.conversationId == conversationId else { return nil }
                return planRuntimeAction(
                    "plan_apply_screening_result",
                    text: screeningText,
                    shouldRunInline: shouldRunPlanInline,
                    planIntentConversationId: conversationId
                )
            }
            guard await MainActor.run(body: { self.conversationId == conversationId }) else {
                await MainActor.run {
                    cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
                }
                return .completed
            }
            let screeningStatus = screeningSnapshot?.output?.chatContentOverride
                ?? "Starting codebase analysis..."
            let skipFullPipeline = screeningSnapshot?.output?.skipFullPlanPipeline == true
                || parsePlanScreeningDecision(from: screeningText) == .noPlanNeeded

            if skipFullPipeline {
                await MainActor.run {
                    guard self.conversationId == conversationId else { return }
                    chatStore.updateLastAssistantMessage(
                        content: screeningStatus,
                        in: conversationId,
                        persistImmediately: true
                    )
                    chatStore.setLastAssistantStreaming(true, in: conversationId)
                    planFlowPhase = .idle
                    planningState = .idle
                    clearPlanStreamingState()
                    _ = planRuntimeAction(
                        "plan_reset",
                        shouldRunInline: shouldRunPlanInline,
                        planIntentConversationId: conversationId
                    )
                }
                return .continueWithDirectChat(
                    prompt: fullTurnPromptForScreeningFallback,
                    attachments: attachmentsToSend
                )
            }

            // Finalize screening in chat and open plan panel
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                chatStore.updateLastAssistantMessage(
                    content: screeningStatus,
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                // Open the plan panel AFTER screening, BEFORE deep analysis
                if !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        } else {
            // Screening was already done (auto-detect case) — just open the panel
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                if !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        }

        // ========================
        // PHASE 1: Codebase Analysis
        // ========================
        let shouldStartPhase1 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            _ = planRuntimeAction(
                "plan_prepare_phase1_analysis_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
            clearPlanStreamingState()
            return true
        }
        guard shouldStartPhase1 else {
            // Conversation changed before Phase 1 could start.
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }

        let analysisPrompt = await MainActor.run { () -> String in
            guard self.conversationId == conversationId else { return "" }
            return buildPhase1AnalysisPrompt(
                userRequest: planUserRequest,
                planIntentConversationId: conversationId
            )
        }
        guard !analysisPrompt.isEmpty else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }
        let analysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: analysisPrompt,
            context: ctx,
            attachments: attachmentsToSend,
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

        let analysisText = analysisResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let analysisRuntimeSnapshot = await MainActor.run { () -> MainChatRuntimeSnapshotBridge? in
            guard self.conversationId == conversationId else { return nil }
            return planRuntimeAction(
                "plan_apply_analysis_result",
                text: analysisText,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
        }
        guard await MainActor.run(body: { self.conversationId == conversationId }) else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }
        let shouldRequestClarifications = analysisRuntimeSnapshot?.plan?.phase == .questioning

        await MainActor.run {
            guard self.conversationId == conversationId else { return }
            updatePlanStreamingContent(analysisText, conversationId: conversationId)
            chatStore.updateLastAssistantMessage(
                content: analysisText,
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            let transitionMessage = shouldRequestClarifications
                ? "Analysis complete. Checking if clarifications are needed..."
                : "Analysis complete. Generating definitive plan in the Plan Panel..."
            chatStore.addMessage(
                ChatMessage(id: UUID(), role: .assistant, content: transitionMessage),
                to: conversationId
            )
            // Panel is already opened in Phase 0 — no need to open here
        }

        if !shouldRequestClarifications {
            // Skip the question phase for well-scoped requests and continue directly.
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                planningState = .idle
                clearPlanStreamingState()
            }
            try await runPlanFlowPhase3(
                provider: provider,
                ctx: ctx,
                conversationId: conversationId,
                shouldRunPlanInline: shouldRunPlanInline
            )
            return .completed
        }

        // ========================
        // PHASE 2: Clarification Questions
        // ========================
        let phase2StartContext = await MainActor.run { () -> (shouldStart: Bool, questionEpochBaseline: Int) in
            guard self.conversationId == conversationId else {
                return (
                    false,
                    planQuestionToolEpoch(for: conversationId)
                )
            }
            clearPlanStreamingState()
            _ = planRuntimeAction(
                "plan_prepare_phase2_questions_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
            let questionAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: questionAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            chatStore.updateLastAssistantMessage(
                content: "Generating clarification questions...",
                in: conversationId,
                persistImmediately: true
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: questionAssistantMessageId,
                providerId: provider.id
            )
            return (
                true,
                planQuestionToolEpoch(for: conversationId)
            )
        }
        let shouldStartPhase2 = phase2StartContext.shouldStart
        let questionToolEpochBaseline = phase2StartContext.questionEpochBaseline
        guard shouldStartPhase2 else {
            // Conversation changed before Phase 2.
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }

        let questionPrompt = await MainActor.run { () -> String in
            guard self.conversationId == conversationId else { return "" }
            return buildPhase2QuestionPrompt(
                userRequest: planUserRequest,
                analysisContext: analysisText,
                planIntentConversationId: conversationId
            )
        }
        guard !questionPrompt.isEmpty else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }
        let questionResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: questionPrompt,
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

        let questionText = questionResult.trimmingCharacters(in: .whitespacesAndNewlines)
        let didReceiveToolDrivenQuestionnaire = await MainActor.run { () -> Bool in
            planQuestionToolEpoch(for: conversationId) > questionToolEpochBaseline
        }
        if didReceiveToolDrivenQuestionnaire {
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            return .completed
        }

        let questionRuntimeSnapshot = await MainActor.run { () -> MainChatRuntimeSnapshotBridge? in
            guard self.conversationId == conversationId else { return nil }
            return planRuntimeAction(
                "plan_apply_question_result",
                text: questionText,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
        }
        guard await MainActor.run(body: { self.conversationId == conversationId }) else {
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return .completed
        }

        if let questionRuntimeSnapshot,
           questionRuntimeSnapshot.plan?.planningStateKind == .awaitingClarification,
           let questions = questionRuntimeSnapshot.plan?.clarificationQuestions {
            // Parse questions and pause for user input
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                _ = planRuntimeAction(
                    "plan_receive_clarification_questions",
                    questions: questions,
                    shouldRunInline: shouldRunPlanInline,
                    planIntentConversationId: conversationId
                )
                updatePlanStreamingContent(questionText, conversationId: conversationId)
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
            // STOP — Phase 3 will be triggered by submitPlanClarificationAnswers() → continuePlanFlowPhase3()
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            return .completed
        }
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
        let phase2Summary = questionRuntimeSnapshot?.output?.chatContentOverride
            ?? "Question phase completed. Generating plan..."
        await MainActor.run {
            guard shouldMutatePlanState(
                targetConversationId: conversationId,
                currentConversationId: self.conversationId
            ) else { return }
            _ = planRuntimeAction(
                "plan_prepare_phase3_generation_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
            chatStore.addMessage(
                ChatMessage(id: UUID(), role: .assistant, content: phase2Summary),
                to: conversationId
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearPlanStreamingState()
        }
        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
        return .completed
    }
}
