import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func runPlanFlowPhase3(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 3: Plan Generation
        // ========================
        let phase3StartContext = await MainActor.run { () -> (shouldStart: Bool, questionEpochBaseline: Int) in
            guard self.conversationId == conversationId else {
                return (
                    false,
                    planQuestionToolEpoch(for: conversationId)
                )
            }
            _ = planRuntimeAction(
                "plan_prepare_phase3_generation_prompt",
                text: planUserRequest,
                shouldRunInline: shouldRunPlanInline
            )
            let generationAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: generationAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: generationAssistantMessageId,
                providerId: provider.id
            )
            chatStore.updateLastAssistantMessage(
                content: "Generating definitive plan...",
                in: conversationId,
                persistImmediately: true
            )
            return (
                true,
                planQuestionToolEpoch(for: conversationId)
            )
        }
        let shouldStartPhase3 = phase3StartContext.shouldStart
        let questionToolEpochBaseline = phase3StartContext.questionEpochBaseline
        guard shouldStartPhase3 else {
            // Conversation changed before Phase 3.
            await MainActor.run {
                cleanupPlanFlowAfterConversationSwitch(targetConversationId: conversationId)
            }
            return
        }

        let generationPrompt = buildPhase3GenerationPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let generationResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: generationPrompt,
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

        let didReceiveToolDrivenQuestionnaire = await MainActor.run { () -> Bool in
            planQuestionToolEpoch(for: conversationId) > questionToolEpochBaseline
        }
        if didReceiveToolDrivenQuestionnaire {
            clearStreamingReasoning(for: conversationId)
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            return
        }

        var full = generationResult

        var generationRuntimeSnapshot = planRuntimeAction(
            "plan_apply_generation_result",
            text: full,
            shouldRunInline: shouldRunPlanInline
        )

        if let runtimeSnapshot = generationRuntimeSnapshot,
           runtimeSnapshot.plan?.planningStateKind == .awaitingClarification,
           let _ = runtimeSnapshot.plan?.clarificationQuestions
        {
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                updatePlanStreamingContent(full, conversationId: conversationId)
                chatStore.updateLastAssistantMessage(
                    content: "Additional clarifications needed — answer in the plan panel.",
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
            clearStreamingReasoning(for: conversationId)
            finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)
            return
        }

        let maxRepairAttempts = 2
        var repairAttempt = 0
        while generationRuntimeSnapshot?.plan?.phase != .proposalReady,
              repairAttempt < maxRepairAttempts,
              generationRuntimeSnapshot?.output?.generatedPrompt != nil {
            repairAttempt += 1

            await MainActor.run {
                clearPlanStreamingState()
                chatStore.updateLastAssistantMessage(
                    content: "Regenerating plan... (attempt \(repairAttempt)/\(maxRepairAttempts))",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(true, in: conversationId)
            }

            let repairPrompt = buildPhase3TodoComplianceRepairPrompt(
                userRequest: planUserRequest,
                analysisContext: planAnalysisContext,
                clarificationAnswers: planClarificationAnswers,
                invalidPlanOutput: full
            )

            let repairedResult = try await flowCoordinator.runStream(
                provider: provider,
                prompt: repairPrompt,
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

            full = repairedResult
            generationRuntimeSnapshot = planRuntimeAction(
                "plan_apply_generation_result",
                text: full,
                shouldRunInline: shouldRunPlanInline
            )
        }

        await MainActor.run {
            guard shouldMutatePlanState(
                targetConversationId: conversationId,
                currentConversationId: self.conversationId
            ) else { return }
            updatePlanStreamingContent(full, conversationId: conversationId)
        }
        chatStore.setLastAssistantStreaming(false, in: conversationId)
        clearStreamingReasoning(for: conversationId)
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .success)

        let runtimePlan = generationRuntimeSnapshot?.plan
        let options = runtimePlan.map(planOptionsFromRuntimeSnapshot) ?? []
        let canonicalTodos = runtimePlan?.canonicalTodos ?? []

        if generationRuntimeSnapshot?.plan?.phase == .proposalReady, !options.isEmpty {
            let board = makePlanBoardFromRuntimePlan(runtimePlan, options: options)
            chatStore.setPlanBoard(board, for: conversationId)
            let currentConv = chatStore.conversation(for: conversationId)
            let summaryTitle = runtimePlan?.summaryTitle ?? board.goal
            let todoMarkdown = canonicalTodos.enumerated().map { idx, t in
                "  \(idx + 1). \(t)"
            }.joined(separator: "\n")
            let recap: String
            if todoMarkdown.isEmpty {
                recap = "Plan ready: **\(summaryTitle)**\n\nOpen the Plan Panel to review and build."
            } else {
                recap = """
                Plan ready: **\(summaryTitle)**

                Steps:
                \(todoMarkdown)

                Open the Plan Panel to review and build.
                """
            }
            chatStore.updateLastAssistantMessage(
                content: recap,
                in: conversationId,
                persistImmediately: true
            )

            _ = planHistoryStore.createEntry(
                conversationId: conversationId,
                contextId: currentConv?.contextId,
                contextFolderPath: currentConv?.contextFolderPath,
                title: summaryTitle,
                markdown: full,
                options: options,
                chosenPath: board.chosenPath,
                tags: [],
                sourceMessageId: nil
            )

            inlinePlanSummaries.removeValue(forKey: conversationId)

            if shouldRunPlanInline {
                let contextId = currentConv?.contextId
                let contextFolderPath = currentConv?.contextFolderPath
                let planConvId = chatStore.getOrCreateConversationForMode(
                    contextId: contextId, contextFolderPath: contextFolderPath,
                    mode: .plan)
                chatStore.setPlanBoard(board, for: planConvId)
            }

            await MainActor.run {
                guard self.conversationId == conversationId else {
                    return
                }
                _ = planRuntimeAction(
                    "plan_store_proposal",
                    planContent: full,
                    optionFullTexts: options.map(\.fullText),
                    shouldRunInline: shouldRunPlanInline
                )
                if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        } else {
            chatStore.updateLastAssistantMessage(
                content: "Plan generation failed. Please try again.",
                in: conversationId,
                persistImmediately: true
            )
            await MainActor.run {
                guard shouldMutatePlanState(
                    targetConversationId: conversationId,
                    currentConversationId: self.conversationId
                ) else { return }
                clearPlanStreamingState()
                _ = planRuntimeAction(
                    "plan_reset",
                    shouldRunInline: shouldRunPlanInline
                )
            }
        }
    }

    private func planOptionsFromRuntimeSnapshot(_ runtimePlan: MainChatPlanSnapshotBridge) -> [PlanOption] {
        runtimePlan.optionFullTexts.enumerated().map { index, fullText in
            PlanOption(
                id: index + 1,
                title: runtimePlan.optionTitles.indices.contains(index)
                    ? runtimePlan.optionTitles[index]
                    : "Option \(index + 1)",
                fullText: fullText
            )
        }
    }

    private func makePlanBoardFromRuntimePlan(
        _ runtimePlan: MainChatPlanSnapshotBridge?,
        options: [PlanOption]
    ) -> PlanBoard {
        let canonicalTodos = runtimePlan?.canonicalTodos ?? []
        let steps = canonicalTodos.enumerated().map { index, title in
            PlanStep(
                id: String(index + 1),
                title: title,
                description: title,
                targetFile: nil,
                status: .pending
            )
        }
        return PlanBoard(
            goal: runtimePlan?.summaryTitle ?? runtimePlan?.userRequest ?? "Operational plan in progress",
            options: options,
            chosenPath: runtimePlan?.chosenPath,
            steps: steps,
            updatedAt: .now,
            walkthroughMarkdown: nil
        )
    }
}
