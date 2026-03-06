import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func finalizeToolTraceTurn(
        _ active: ToolTraceTurnContext,
        outcome: ToolTraceTurnOutcome
    ) {
        let finalOutcome: ToolTraceTurnOutcome = {
            let pendingPolicyQueue = policyAckBlockedQueue[active.assistantMessageId] ?? []
            let policySatisfied = policyAckStateByMessage[active.assistantMessageId]?.isSatisfied == true
            if !pendingPolicyQueue.isEmpty, !policySatisfied {
                appendTechnicalErrorMessage(
                    "[Policy error] Required AGENTS/SKILL acknowledgment did not arrive before queued operational events could be applied.",
                    in: active.conversationId
                )
                return .failed
            }
            return outcome
        }()
        finalizeAutoTodoIfNeeded(
            messageId: active.assistantMessageId,
            outcome: finalOutcome,
            providerId: active.providerId,
            conversationId: active.conversationId
        )
        toolTraceStore.finalizeTurn(
            conversationId: active.conversationId,
            assistantMessageId: active.assistantMessageId
        )
        toolTraceNextSequenceByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalSeenByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalCountByMessage.removeValue(forKey: active.assistantMessageId)
        policyAckStateByMessage.removeValue(forKey: active.assistantMessageId)
        policyAckBlockedQueue.removeValue(forKey: active.assistantMessageId)
        autoTodoIdByMessage.removeValue(forKey: active.assistantMessageId)
        autoTodoCompletedOperationsByMessage.removeValue(forKey: active.assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(active.assistantMessageId)
    }

    @MainActor
    internal func finalizeAutoTodoIfNeeded(
        messageId: UUID,
        outcome: ToolTraceTurnOutcome,
        providerId: String,
        conversationId: UUID
    ) {
        if let autoTodoId = autoTodoIdByMessage[messageId],
           !didReceiveExplicitTodoByMessage.contains(messageId) {
            let finalStatus = autoTodoFinalStatus(for: outcome)
            todoStore.setStatus(id: autoTodoId, status: finalStatus)
            let currentTodo = todoStore.todos.first(where: { $0.id == autoTodoId })
            let notes: String = {
                switch finalStatus {
                case .done:
                    return "Auto-generated: all trace activities completed."
                case .blocked:
                    return "Auto-generated: execution interrupted or failed."
                default:
                    return "Auto-generated: status updated."
                }
            }()
            emitAutoTodoTraceUpdate(
                todoId: autoTodoId,
                title: currentTodo?.title ?? "Auto TODO",
                status: finalStatus,
                notes: notes,
                linkedFiles: currentTodo?.linkedFiles ?? [],
                providerId: providerId,
                conversationId: conversationId,
                timestamp: .now
            )
        }
    }

    @MainActor
    internal func resolveToolTraceTurn(conversationId: UUID?, providerId: String) -> ToolTraceTurnContext? {
        let activeTurn = conversationId.flatMap { activeToolTraceTurnsByConversation[$0] }
        if let activeTurn,
           activeTurn.providerId != providerId,
           !isSwarmPolicyAckExemptProvider(providerId) {
            return nil
        }
        let activeTarget = activeTurn.map {
            ToolTraceBindingTarget(
                conversationId: $0.conversationId,
                assistantMessageId: $0.assistantMessageId
            )
        }
        if activeTarget == nil,
           let conversationId,
           !chatStore.isTaskActive(for: conversationId) {
            return nil
        }
        let fallbackAssistantMessageId = conversationId.flatMap { id in
            chatStore.conversation(for: id)?
                .messages
                .last(where: { $0.role == .assistant })?
                .id
        }
        guard let target = ToolTraceBindingResolver.resolve(
            activeTurn: activeTarget,
            requestedConversationId: conversationId,
            fallbackAssistantMessageId: fallbackAssistantMessageId
        ) else {
            return nil
        }
        let fallbackTurn = ToolTraceTurnContext(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        if toolTraceNextSequenceByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            let next = (existing.last?.sequence ?? 0) + 1
            toolTraceNextSequenceByMessage[target.assistantMessageId] = max(1, next)
        }
        if toolTraceOperationalSeenByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalSeenByMessage[target.assistantMessageId] = existing.contains {
                isOperationalTraceEvent($0)
            }
        }
        if toolTraceOperationalCountByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalCountByMessage[target.assistantMessageId] = existing.reduce(into: 0) { partial, event in
                if isOperationalTraceEvent(event) {
                    partial += 1
                }
            }
        }
        if isSwarmPolicyAckExemptProvider(providerId) {
            policyAckStateByMessage.removeValue(forKey: target.assistantMessageId)
            policyAckFailedMessages.remove(target.assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: target.assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurnsByConversation[target.conversationId] = fallbackTurn
        return fallbackTurn
    }

    @MainActor
    internal func appendToolTraceEvent(
        activity: TaskActivity,
        rawKind: EventKind,
        providerId: String,
        conversationId: UUID?
    ) {
        guard ToolTraceVisibility.shouldInclude(activity: activity) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let sequence = toolTraceNextSequenceByMessage[turn.assistantMessageId] ?? 1
        let event = ToolTraceEvent(
            sequence: sequence,
            timestamp: activity.timestamp,
            providerId: providerId,
            conversationId: turn.conversationId,
            assistantMessageId: turn.assistantMessageId,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: activity.payload,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId,
            rawKind: rawKind.rawValue
        )
        toolTraceStore.append(event: event)
        toolTraceNextSequenceByMessage[turn.assistantMessageId] = sequence + 1
        if isOperationalTraceActivity(activity) {
            toolTraceOperationalSeenByMessage[turn.assistantMessageId] = true
            let current = toolTraceOperationalCountByMessage[turn.assistantMessageId] ?? 0
            toolTraceOperationalCountByMessage[turn.assistantMessageId] = current + 1
        }
        updateStreamingToolSegment(newEvent: event, conversationId: turn.conversationId, assistantMessageId: turn.assistantMessageId)
    }

    internal func updateStreamingToolSegment(
        newEvent: ToolTraceEvent,
        conversationId: UUID,
        assistantMessageId: UUID
    ) {
        guard sequentialStreamingLayoutEnabled else { return }
        guard conversationId == self.conversationId else { return }
        // Ensure the incoming event belongs to the active streaming assistant turn.
        guard let activeAssistantMessageId = chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id,
            activeAssistantMessageId == assistantMessageId
        else {
            return
        }
        let segId = "tools-\(streamingSegmentTurnIndex)"
        if let idx = streamingSegments.firstIndex(where: { $0.id == segId }) {
            if case .toolTrace(var existing) = streamingSegments[idx].kind {
                if let updateIdx = existing.firstIndex(where: { $0.id == newEvent.id }) {
                    existing[updateIdx] = newEvent
                } else {
                    existing.append(newEvent)
                }
                streamingSegments[idx].kind = .toolTrace(existing)
            }
        } else {
            streamingSegments.append(MessageSegment(id: segId, kind: .toolTrace([newEvent])))
        }
    }

}
