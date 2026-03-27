import CoderEngine
import Foundation

extension ChatPanelView {
    var manualPlanBuildKickoffMessage: String {
        "Proceed with the plan."
    }

    @MainActor
    internal func syncAgentBackedPlanAfterStream(
        conversationId: UUID,
        fullText: String,
        shouldRunPlanInline: Bool,
        isBuildContext: Bool
    ) {
        guard !isBuildContext else { return }
        let planningSessionActive = isPlanBuildGuardActive(
            phase: planFlowPhase,
            planningState: planningState,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        ) || coderMode == .plan || shouldRunPlanInline
        guard planningSessionActive else {
            return
        }

        let classification = PlanOutputClassifier.classify(
            fullText: fullText,
            current: planFlowPhase,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        switch classification.planningState {
        case .awaitingClarification(let questions):
            planningState = .awaitingClarification(questions: questions)
            planFlowPhase = .questioning
            planClarificationQuestionnaire = PlanOptionsParser.parseClarificationQuestionnaire(
                from: questions
            )
            updatePlanStreamingContent(questions, conversationId: conversationId)
            _ = applyPlanUIIntent(
                "plan_receive_clarification_questions",
                conversationId: conversationId,
                text: questions
            )
            if shouldAutoOpenPlanPanel(trigger: .awaitingClarification, planToggleEnabled: planToggleEnabled),
               !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }

        case .awaitingChoice(let planContent, let options):
            planningState = .awaitingChoice(planContent: planContent, options: options)
            planFlowPhase = .proposalReady
            planClarificationQuestionnaire = nil
            planClarificationAnswers = ""
            let board = buildAgentBackedPlanBoard(
                planContent: planContent,
                options: options
            )
            chatStore.setPlanBoard(board, for: conversationId)
            if let currentConversation = chatStore.conversation(for: conversationId),
               let assistantMessageId = currentConversation.messages.last(where: { $0.role == .assistant })?.id {
                let historyEntry = planHistoryStore.createEntry(
                    conversationId: conversationId,
                    contextId: currentConversation.contextId,
                    contextFolderPath: currentConversation.contextFolderPath,
                    title: board.goal,
                    markdown: planContent,
                    options: options,
                    chosenPath: board.chosenPath,
                    tags: [],
                    sourceMessageId: assistantMessageId
                )
                chatStore.attachPlanEntry(
                    toMessageId: assistantMessageId,
                    conversationId: conversationId,
                    entry: historyEntry
                )
            }
            _ = planRuntimeAction(
                "plan_store_proposal",
                planContent: planContent,
                optionFullTexts: options.map(\.fullText),
                shouldRunInline: shouldRunPlanInline,
                planIntentConversationId: conversationId
            )
            if shouldAutoOpenPlanPanel(trigger: .awaitingChoice, planToggleEnabled: planToggleEnabled),
               !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }

        case .idle, .none:
            if classification.hasClarificationQuestions {
                planFlowPhase = .questioning
            } else if classification.hasStrictOptions {
                planFlowPhase = .proposalReady
            } else if hasNoQuestionsNeededSignal(fullText) {
                planFlowPhase = .generating
            } else {
                planningState = .idle
                planFlowPhase = .idle
            }
        }
    }

    @MainActor
    internal func beginManualPlanBuildChatTransition(
        conversationId: UUID,
        providerId: String
    ) {
        planningState = .idle
        planClarificationQuestionnaire = nil
        clearPlanStreamingState()
        _ = applyPlanUIIntent(
            "begin_plan_build",
            conversationId: conversationId
        )

        chatStore.addMessage(
            ChatMessage(
                role: .user,
                content: manualPlanBuildKickoffMessage,
                isStreaming: false
            ),
            to: conversationId
        )

        let planBuildAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: planBuildAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: conversationId
        )
        suppressedEmptyBuildAssistantMessageIds.insert(planBuildAssistantMessageId)
        startToolTraceTurn(
            conversationId: conversationId,
            assistantMessageId: planBuildAssistantMessageId,
            providerId: providerId
        )
        chatStore.beginTask(conversationId: conversationId)
        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: conversationId
        ) {
            clearTaskActivityPipeline()
        }
        scheduleFallbackTurnStartEvent(
            conversationId: conversationId,
            providerId: providerId
        )
    }

    private func buildAgentBackedPlanBoard(
        planContent: String,
        options: [PlanOption]
    ) -> PlanBoard {
        let board = PlanBoard.build(from: planContent, options: options)
        return PlanBoard(
            goal: board.goal,
            options: options,
            chosenPath: nil,
            steps: board.steps,
            updatedAt: .now,
            walkthroughMarkdown: nil
        )
    }
}
