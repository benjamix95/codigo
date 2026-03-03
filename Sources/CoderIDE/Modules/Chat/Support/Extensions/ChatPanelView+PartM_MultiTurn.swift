import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func runMultiTurnPlanFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 1: Codebase Analysis
        // ========================
        let shouldStartPhase1 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .analyzing
            clearPlanStreamingState()
            return true
        }
        guard shouldStartPhase1 else {
            // Conversation changed before Phase 1 could start.
            return
        }

        let analysisPrompt = buildPhase1AnalysisPrompt(userRequest: planUserRequest)
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
        let shouldRequestClarifications = shouldAskPlanClarifications(
            analysisText: analysisText,
            userRequest: planUserRequest
        )

        await MainActor.run {
            guard self.conversationId == conversationId else { return }
            planAnalysisContext = analysisText
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
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
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
            return
        }

        // ========================
        // PHASE 2: Clarification Questions
        // ========================
        let shouldStartPhase2 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            clearPlanStreamingState()
            planFlowPhase = .questioning
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
            return true
        }
        guard shouldStartPhase2 else {
            // Conversation changed before Phase 2.
            return
        }

        let questionPrompt = buildPhase2QuestionPrompt(
            userRequest: planUserRequest,
            analysisContext: analysisResult
        )
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
        let questionDecision = decidePlanQuestionPhaseOutput(
            questionText,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        if case .clarification(let questions) = questionDecision {
            // Parse questions and pause for user input
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                planClarificationCycles += 1
                planningState = .awaitingClarification(questions: questions)
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
            return
        }

        // No structured clarification questions — proceed directly to Phase 3.
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
        let phase2Summary = hasNoQuestionsNeededSignal(questionText)
            ? "No questions needed. Generating plan..."
            : "Question phase completed. Generating plan..."
        await MainActor.run {
            guard shouldMutatePlanState(
                targetConversationId: conversationId,
                currentConversationId: self.conversationId
            ) else { return }
            planningState = .idle
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
    }

}
