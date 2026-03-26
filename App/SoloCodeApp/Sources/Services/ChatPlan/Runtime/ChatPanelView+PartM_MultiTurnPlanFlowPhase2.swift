import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Fase 2 — domande di chiarimento e conclusivi verso fase 3 se non serve attendere l’utente.
    internal func runMultiTurnPlanFlowPhase2(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool,
        analysisText: String
    ) async throws -> MultiTurnPlanFlowOutcome {
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
