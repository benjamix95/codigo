import Foundation
import CoderEngine

extension ChatPanelView {
    internal func currentInstructionPolicyBundle() -> InstructionPolicyBundle {
        let hints = traceWorkspaceHints(for: effectiveContext)
        return InstructionPolicyBundle.load(workspacePaths: hints)
    }

    internal func expectedPolicyAckHash() -> String? {
        guard uiSettings.agentsHardBlockEnabled else { return nil }
        let bundle = currentInstructionPolicyBundle()
        let hash = bundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }
        return hash
    }

    internal func initializePolicyAckStateIfNeeded(for assistantMessageId: UUID) {
        guard let expectedHash = expectedPolicyAckHash() else {
            toolRuntime.policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            toolRuntime.policyAckFailedMessages.remove(assistantMessageId)
            return
        }
        guard !toolRuntime.policyAckFailedMessages.contains(assistantMessageId) else { return }
        if toolRuntime.policyAckStateByMessage[assistantMessageId] == nil {
            toolRuntime.policyAckStateByMessage[assistantMessageId] = PolicyAckState(expectedHash: expectedHash)
        }
    }

    @MainActor
    internal func startToolTraceTurn(conversationId: UUID, assistantMessageId: UUID, providerId: String) {
        if let previous = toolRuntime.activeToolTraceTurnsByConversation[conversationId],
           previous.assistantMessageId != assistantMessageId {
            let previousEvents = toolTraceStore.events(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            let hasRunningOperations = previousEvents.contains { $0.isRunning }
            let rolloverOutcome: ToolTraceTurnOutcome = hasRunningOperations ? .aborted : .success
            let previousPolicySatisfied = toolRuntime.policyAckStateByMessage[previous.assistantMessageId]?.isSatisfied == true
            let previousTodoState = toolRuntime.toolStartRequirementsStateByMessage[previous.assistantMessageId]
            finalizeAutoTodoIfNeeded(
                messageId: previous.assistantMessageId,
                outcome: rolloverOutcome,
                providerId: previous.providerId,
                conversationId: previous.conversationId
            )
            toolTraceStore.finalizeTurn(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            toolRuntime.toolTraceNextSequenceByMessage.removeValue(forKey: previous.assistantMessageId)
            toolRuntime.toolTraceOperationalSeenByMessage.removeValue(forKey: previous.assistantMessageId)
            toolRuntime.toolTraceOperationalCountByMessage.removeValue(forKey: previous.assistantMessageId)
            toolRuntime.policyAckStateByMessage.removeValue(forKey: previous.assistantMessageId)
            toolRuntime.toolStartRequirementsStateByMessage.removeValue(forKey: previous.assistantMessageId)
            // Flush any remaining blocked events before discarding the queue
            if let remainingQueued = toolRuntime.policyAckBlockedQueue.removeValue(forKey: previous.assistantMessageId), !remainingQueued.isEmpty {
                if previousPolicySatisfied {
                    for event in remainingQueued {
                        handleRawStreamEvent(
                            type: event.type,
                            payload: event.payload,
                            providerId: event.providerId,
                            conversationId: event.conversationId,
                            shouldApplyPipelineArtifacts: event.shouldApplyPipelineArtifacts
                        )
                    }
                } else {
                    appendTechnicalErrorMessage(
                        "[Policy error] Required AGENTS/SKILL acknowledgment did not arrive before the turn was closed.",
                        in: previous.conversationId
                    )
                }
            }
            toolRuntime.policyAckFailedMessages.remove(previous.assistantMessageId)
            conversationRuntime.autoTodoRuntimeStateByMessage.removeValue(
                forKey: previous.assistantMessageId.uuidString.lowercased()
            )
            conversationRuntime.didReceiveExplicitTodoByMessage.remove(previous.assistantMessageId)
        }
        let turn = ToolTraceTurnContext(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
        let hasExistingScopedTodos = !todoStore.displayTodosForChat(for: conversationId).isEmpty
        let hasExistingPlanBoard = !(chatStore.planBoard(for: conversationId)?.steps.isEmpty ?? true)
        let concreteScopedActivities = taskActivityStore.concreteNonSwarmActivities(for: conversationId)
        let hasConcreteScopedActivities = !concreteScopedActivities.isEmpty
        let seededTodoRequirementState = ToolStartRequirementsState(
            didSeeTodoWrite: hasExistingScopedTodos || hasExistingPlanBoard || hasConcreteScopedActivities,
            violationEmitted: false
        )
        toolRuntime.activeToolTraceTurnsByConversation[conversationId] = turn
        toolRuntime.toolTraceNextSequenceByMessage[assistantMessageId] = 1
        toolRuntime.toolTraceOperationalSeenByMessage[assistantMessageId] = false
        toolRuntime.toolTraceOperationalCountByMessage[assistantMessageId] = 0
        toolRuntime.toolStartRequirementsStateByMessage[assistantMessageId] = seededTodoRequirementState
        conversationRuntime.autoTodoRuntimeStateByMessage.removeValue(forKey: assistantMessageId.uuidString.lowercased())
        conversationRuntime.didReceiveExplicitTodoByMessage.remove(assistantMessageId)
        if isSwarmPolicyAckExemptProvider(providerId) {
            toolRuntime.policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            toolRuntime.policyAckFailedMessages.remove(assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
    }

    /// Finalizza il tool trace per un turno. Passa sempre `conversationId` quando possibile:
    /// con `nil` si chiudono **tutti** i turni attivi (solo per interrupt/shutdown globale).
    @MainActor
    internal func finalizeToolTraceTurn(conversationId: UUID?, outcome: ToolTraceTurnOutcome? = nil) {
        let finalOutcome = outcome ?? toolTraceTurnOutcome(for: flowCoordinator.state)
        if let conversationId, conversationId == self.conversationId {
            lastTaskCompletionOutcome = finalOutcome
        }

        if let conversationId {
            guard let active = toolRuntime.activeToolTraceTurnsByConversation[conversationId] else { return }
            finalizeToolTraceTurn(active, outcome: finalOutcome)
            toolRuntime.activeToolTraceTurnsByConversation.removeValue(forKey: conversationId)
            return
        }

        let activeTurns = Array(toolRuntime.activeToolTraceTurnsByConversation.values)
        for active in activeTurns {
            finalizeToolTraceTurn(active, outcome: finalOutcome)
        }
        toolRuntime.activeToolTraceTurnsByConversation.removeAll()
    }
}
