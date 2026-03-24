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
            recoverPolicyAckFromPersistedAssistantMessageIfNeeded(
                assistantMessageId: active.assistantMessageId,
                providerId: active.providerId,
                conversationId: active.conversationId
            )
            let pendingPolicyQueue = toolRuntime.policyAckBlockedQueue[active.assistantMessageId] ?? []
            let policySatisfied = toolRuntime.policyAckStateByMessage[active.assistantMessageId]?.isSatisfied == true
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
        toolRuntime.toolTraceNextSequenceByMessage.removeValue(forKey: active.assistantMessageId)
        toolRuntime.toolTraceOperationalSeenByMessage.removeValue(forKey: active.assistantMessageId)
        toolRuntime.toolTraceOperationalCountByMessage.removeValue(forKey: active.assistantMessageId)
        toolRuntime.policyAckStateByMessage.removeValue(forKey: active.assistantMessageId)
        toolRuntime.toolStartRequirementsStateByMessage.removeValue(forKey: active.assistantMessageId)
        toolRuntime.policyAckBlockedQueue.removeValue(forKey: active.assistantMessageId)
        conversationRuntime.autoTodoRuntimeStateByMessage.removeValue(
            forKey: active.assistantMessageId.uuidString.lowercased()
        )
        conversationRuntime.didReceiveExplicitTodoByMessage.remove(active.assistantMessageId)
    }

    @MainActor
    internal func finalizeAutoTodoIfNeeded(
        messageId: UUID,
        outcome: ToolTraceTurnOutcome,
        providerId: String,
        conversationId: UUID
    ) {
        guard !conversationRuntime.didReceiveExplicitTodoByMessage.contains(messageId) else { return }
        applyAutoTodoRuntimeIntent(
            "auto_todo_finalize_runtime",
            assistantMessageId: messageId,
            providerId: providerId,
            conversationId: conversationId,
            outcome: outcome
        )
    }

    @MainActor
    internal func resolveToolTraceTurn(conversationId: UUID?, providerId: String) -> ToolTraceTurnContext? {
        let activeTurn = conversationId.flatMap { toolRuntime.activeToolTraceTurnsByConversation[$0] }
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
            fallbackStreamingAssistantMessageId(in: chatStore.conversation(for: id))
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
        if toolRuntime.toolTraceNextSequenceByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            let next = (existing.last?.sequence ?? 0) + 1
            toolRuntime.toolTraceNextSequenceByMessage[target.assistantMessageId] = max(1, next)
        }
        if toolRuntime.toolTraceOperationalSeenByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolRuntime.toolTraceOperationalSeenByMessage[target.assistantMessageId] = existing.contains {
                isOperationalTraceEvent($0)
            }
        }
        if toolRuntime.toolTraceOperationalCountByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolRuntime.toolTraceOperationalCountByMessage[target.assistantMessageId] = existing.reduce(into: 0) { partial, event in
                if isOperationalTraceEvent(event) {
                    partial += 1
                }
            }
        }
        if isSwarmPolicyAckExemptProvider(providerId) {
            toolRuntime.policyAckStateByMessage.removeValue(forKey: target.assistantMessageId)
            toolRuntime.policyAckFailedMessages.remove(target.assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: target.assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        toolRuntime.activeToolTraceTurnsByConversation[target.conversationId] = fallbackTurn
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
        let sequence = toolRuntime.toolTraceNextSequenceByMessage[turn.assistantMessageId] ?? 1
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
        toolRuntime.toolTraceNextSequenceByMessage[turn.assistantMessageId] = sequence + 1
        if isOperationalTraceActivity(activity) {
            toolRuntime.toolTraceOperationalSeenByMessage[turn.assistantMessageId] = true
            let current = toolRuntime.toolTraceOperationalCountByMessage[turn.assistantMessageId] ?? 0
            toolRuntime.toolTraceOperationalCountByMessage[turn.assistantMessageId] = current + 1
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
        let segId = "tools-\(streaming.streamingSegmentTurnIndex)"
        if let idx = streaming.streamingSegments.firstIndex(where: { $0.id == segId }) {
            if case .toolTrace(var existing) = streaming.streamingSegments[idx].kind {
                if let updateIdx = existing.firstIndex(where: { $0.id == newEvent.id }) {
                    existing[updateIdx] = newEvent
                } else {
                    existing.append(newEvent)
                }
                streaming.streamingSegments[idx].kind = .toolTrace(existing)
            }
        } else {
            streaming.streamingSegments.append(MessageSegment(id: segId, kind: .toolTrace([newEvent])))
        }
    }

}
