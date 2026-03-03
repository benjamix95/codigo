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
        let shouldStartPhase3 = await MainActor.run { () -> Bool in
            guard self.conversationId == conversationId else { return false }
            planFlowPhase = .generating
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
            return true
        }
        guard shouldStartPhase3 else {
            // Conversation changed before Phase 3.
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

        func parsePlanOptions(_ text: String) -> [PlanOption] {
            let strict = PlanOptionsParser.parseStrict(from: text)
            if !strict.isEmpty { return strict }
            return PlanOptionsParser.parse(from: text)
        }

        func areAllOptionsTodoCompliant(_ options: [PlanOption]) -> Bool {
            guard !options.isEmpty else { return false }
            let compliant = PlanOptionsParser.todoCompliantOptions(from: options)
            return compliant.count == options.count
        }

        var full = generationResult

        // Phase 3 clarification fallback: if the LLM flagged critical ambiguities
        // via a `## Clarifications Needed` section, route back to questioning instead
        // of producing a potentially incorrect plan.
        if planClarificationCycles < 2,
           let clarRange = full.range(of: "## Clarifications Needed")
        {
            let clarificationsText = String(full[clarRange.lowerBound...])
            await MainActor.run {
                guard self.conversationId == conversationId else { return }
                planClarificationCycles += 1
                planFlowPhase = .questioning
                planningState = .awaitingClarification(questions: clarificationsText)
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

        var options = parsePlanOptions(full)

        // Hard enforcement: every option must contain an explicit `## Todo` section.
        let maxRepairAttempts = 2
        var repairAttempt = 0
        while !areAllOptionsTodoCompliant(options), repairAttempt < maxRepairAttempts {
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
            options = parsePlanOptions(full)
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

        if !options.isEmpty, areAllOptionsTodoCompliant(options) {
            let compliantOptions = PlanOptionsParser.todoCompliantOptions(from: options)
            let board = PlanBoard.build(from: full, options: compliantOptions)
            chatStore.setPlanBoard(board, for: conversationId)
            let currentConv = chatStore.conversation(for: conversationId)
            let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
            chatStore.updateLastAssistantMessage(
                content: "Plan ready in Plan Panel: \(parsedSummary.title)",
                in: conversationId,
                persistImmediately: true
            )

            _ = planHistoryStore.createEntry(
                conversationId: conversationId,
                contextId: currentConv?.contextId,
                contextFolderPath: currentConv?.contextFolderPath,
                title: parsedSummary.title,
                markdown: full,
                options: compliantOptions,
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
                planFlowPhase = .proposalReady
                planningState = .awaitingChoice(planContent: full, options: compliantOptions)
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
                planFlowPhase = .idle
                planningState = .idle
            }
        }
    }
}
