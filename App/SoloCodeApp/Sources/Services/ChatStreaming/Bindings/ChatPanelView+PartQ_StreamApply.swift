import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func enqueueMainChatStreamingTextUpdate(
        _ content: String,
        conversationId targetConversationId: UUID?,
        providerId: String?
    ) {
        guard let targetConversationId else { return }
        let effectiveProviderId = providerId ?? resolvedTurnProviderId(for: targetConversationId)
        let replacedPendingLen = streaming.pendingStreamContent?.count ?? 0
        let hadPendingSnapshot = streaming.pendingStreamContent != nil
        if streaming.pendingStreamQueuedAt == nil {
            streaming.pendingStreamQueuedAt = Date()
        } else if hadPendingSnapshot {
            streaming.pendingStreamOverwriteCount &+= 1
        }
        streaming.pendingStreamContent = content
        streaming.pendingStreamConversationId = targetConversationId

        if effectiveProviderId == "codex-cli" {
            streaming.streamThrottleTask?.cancel()
            streaming.streamThrottleTask = nil
            let queuedAt = streaming.pendingStreamQueuedAt ?? Date()
            let queueAgeMs = Int(Date().timeIntervalSince(queuedAt) * 1000)
            let overwriteCount = streaming.pendingStreamOverwriteCount
            let pendingContent = streaming.pendingStreamContent ?? content
            streaming.pendingStreamConversationId = nil
            streaming.pendingStreamContent = nil
            streaming.pendingStreamQueuedAt = nil
            streaming.pendingStreamOverwriteCount = 0
            applyMainChatUIStreamIntent(
                "stream_replace_text",
                conversationId: targetConversationId,
                providerId: effectiveProviderId,
                text: pendingContent
            )
            return
        }

        guard streaming.streamThrottleTask == nil else { return }
        streaming.streamThrottleTask = Task { @MainActor [self] in
            defer { streaming.streamThrottleTask = nil }
            while !Task.isCancelled {
                await Task.yield()
                guard let pendingConversationId = streaming.pendingStreamConversationId,
                      let pendingContent = streaming.pendingStreamContent else {
                    streaming.pendingStreamQueuedAt = nil
                    streaming.pendingStreamOverwriteCount = 0
                    return
                }
                let queuedAt = streaming.pendingStreamQueuedAt ?? Date()
                let queueAgeMs = Int(Date().timeIntervalSince(queuedAt) * 1000)
                let overwriteCount = streaming.pendingStreamOverwriteCount
                streaming.pendingStreamConversationId = nil
                streaming.pendingStreamContent = nil
                streaming.pendingStreamQueuedAt = nil
                streaming.pendingStreamOverwriteCount = 0
                applyMainChatUIStreamIntent(
                    "stream_replace_text",
                    conversationId: pendingConversationId,
                    providerId: effectiveProviderId ?? resolvedTurnProviderId(for: pendingConversationId),
                    text: pendingContent
                )
            }
        }
    }

    @MainActor
    internal func applyStreamingReasoningSnapshot(
        _ content: String,
        conversationId targetConversationId: UUID?
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard shouldUpdateInlineReasoningState(
            eventConversationId: targetConversationId,
            selectedConversationId: conversationId
        ) else { return }

        let groupId = "reasoning-stream"
        if streaming.streamingReasoningConversationId != targetConversationId {
            streaming.streamingReasoningBlocks = []
            streaming.streamingSegments = []
            streaming.streamingSegmentTurnIndex = 0
        }
        streaming.streamingReasoningConversationId = targetConversationId
        streaming.streamingReasoningText = trimmed
        streaming.streamingReasoningBlocks = [ReasoningBlock(id: groupId, text: trimmed)]
        streaming.streamContentVersion &+= 1
    }

    @MainActor
    internal func applyMainChatUIStreamIntent(
        _ intent: String,
        conversationId targetConversationId: UUID?,
        providerId: String?,
        text: String? = nil,
        payload: [String: String] = [:]
    ) {
        let bridgeStartedAt = Date()
        let response = applyMainChatUIIntentBridge(
            intent,
            conversationId: targetConversationId,
            providerId: providerId,
            text: text,
            timestamp: Date(),
            payload: payload,
            preserveLocalMessages: false
        )
        syncConversationRuntimeFromMainChatUIIntent(
            response: response,
            conversationId: targetConversationId
        )
        let applied = response != nil
        let bridgeMs = Int(Date().timeIntervalSince(bridgeStartedAt) * 1000)
        if applied {
            streaming.streamContentVersion &+= 1
        }
        if intent == "stream_replace_text",
           let text,
           !text.isEmpty,
           let targetConversationId,
           let targetMessageId = currentAssistantPipelineTarget(for: targetConversationId)?.messageId
        {
            let contentLookupStartedAt = Date()
            let currentContent = chatStore.conversation(for: targetConversationId)?
                .messages.first(where: { $0.id == targetMessageId })?
                .content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let contentLookupMs = Int(Date().timeIntervalSince(contentLookupStartedAt) * 1000)
            let trimmedIncoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentDiffers = trimmedIncoming != currentContent
            let shouldWrite = currentContent.isEmpty || contentDiffers || !applied
            var updateAssistantMessageMs = 0
            if shouldWrite {
                let updateStartedAt = Date()
                chatStore.updateAssistantMessage(
                    messageId: targetMessageId,
                    content: text,
                    in: targetConversationId,
                    persistImmediately: false
                )
                updateAssistantMessageMs = Int(Date().timeIntervalSince(updateStartedAt) * 1000)
                streaming.lastMainChatStreamApplyAt = Date()
                streaming.lastMainChatStreamApplyLen = trimmedIncoming.count
                if !applied { streaming.streamContentVersion &+= 1 }
            }
        }
        if !applied,
           intent == "stream_apply_raw_event",
           let targetConversationId
        {
            let eventKind = payload["event_kind"] ?? ""
            if let target = currentAssistantPipelineTarget(for: targetConversationId) {
                let pipelineEvents = RawArtifactEventAdapter.events(
                    rawType: eventKind,
                    payload: payload,
                    conversationId: targetConversationId,
                    assistantMessageId: target.messageId,
                    turnId: target.turnId,
                    providerId: providerId ?? ""
                )
                if !pipelineEvents.isEmpty {
                    applyChatPipelineEvents(pipelineEvents)
                }
            }
            streaming.streamContentVersion &+= 1
        }
    }

    internal func discardPendingStreamingState(for targetConversationId: UUID?) {
        streaming.streamThrottleTask?.cancel()
        streaming.streamThrottleTask = nil
        if shouldDiscardPendingStreamSnapshot(
            targetConversationId: targetConversationId,
            pendingConversationId: streaming.pendingStreamConversationId
        ) {
            streaming.pendingStreamContent = nil
            streaming.pendingStreamConversationId = nil
            streaming.streamingSegments.removeAll()
        }
        streaming.planStreamThrottleTask?.cancel()
        streaming.planStreamThrottleTask = nil
        if let targetConversationId,
           streaming.pendingPlanStreamConversationId == targetConversationId {
            streaming.pendingPlanStreamingContent = nil
            streaming.pendingPlanStreamConversationId = nil
        }
    }

    internal func flushStreamingContent() {
        flushStreamingContent(conversationId: nil)
    }

    internal func flushStreamingContent(conversationId targetConversationId: UUID?) {
        let effectiveConversationId = targetConversationId ?? conversationId
        guard effectiveConversationId != nil else { return }
        applyMainChatUIStreamIntent(
            "stream_replace_text",
            conversationId: effectiveConversationId,
            providerId: resolvedTurnProviderId(for: effectiveConversationId)
        )
    }

    internal func clearStreamingReasoning(for conversationId: UUID?) {
        applyMainChatUIStreamIntent(
            "stream_clear_ephemeral_state",
            conversationId: conversationId,
            providerId: resolvedTurnProviderId(for: conversationId)
        )
        guard let id = conversationId else { return }
        let hadInlineReasoning = streaming.streamingReasoningConversationId == id
        let hasSeparateThinkingMessages =
            !(streaming.reasoningMessageIdByConversationAndGroup[id]?.isEmpty ?? true)
        if hadInlineReasoning,
           !hasSeparateThinkingMessages,
           let reasoning = streaming.streamingReasoningText,
           !reasoning.isEmpty
        {
            chatStore.saveReasoningToLastAssistant(reasoning: reasoning, in: id)
        }
        resetReasoningMessageState(for: id)
        streaming.codexLastReasoningLine = nil
        chatStore.removeTrailingEmptyAssistantMessages(in: id)
        if hadInlineReasoning || hasSeparateThinkingMessages {
            streaming.streamingReasoningText = nil
            streaming.streamingReasoningConversationId = nil
            streaming.streamingReasoningBlocks = []
            streaming.streamingSegments = []
            streaming.streamingSegmentTurnIndex = 0
        }
    }
}
