import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func shouldDiscardPendingStreamSnapshot(
    targetConversationId: UUID?,
    pendingConversationId: UUID?
) -> Bool {
    guard let targetConversationId else { return true }
    return pendingConversationId == targetConversationId
}

extension ChatPanelView {
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
        let applied = applyMainChatUIIntentBridge(
            intent,
            conversationId: targetConversationId,
            providerId: providerId,
            text: text,
            timestamp: Date(),
            payload: payload,
            preserveLocalMessages: false
        ) != nil
        if applied {
            streaming.streamContentVersion &+= 1
        }
        if intent == "stream_replace_text",
           let text,
           !text.isEmpty,
           let targetConversationId,
           let targetMessageId = currentAssistantPipelineTarget(for: targetConversationId)?.messageId
        {
            let currentContent = chatStore.conversation(for: targetConversationId)?
                .messages.first(where: { $0.id == targetMessageId })?
                .content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedIncoming = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // `onText` invia tipicamente il testo completo sostituito, non un delta. Confrontiamo con il locale:
            // il vecchio gate “+80 caratteri” saltava riscritture più corte e correzioni. Se il bridge Rust non
            // ha applicato, aggiorniamo sempre il locale (fallback).
            let contentDiffers = trimmedIncoming != currentContent
            let shouldWrite = currentContent.isEmpty || contentDiffers || !applied
            if shouldWrite {
                chatStore.updateAssistantMessage(
                    messageId: targetMessageId,
                    content: text,
                    in: targetConversationId,
                    persistImmediately: false
                )
                if !applied { streaming.streamContentVersion &+= 1 }
            }
        }
        // Safety net: when Rust fails mid-stream, fall through to Swift
        // pipeline for raw event rendering so artifacts still appear.
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

    static func shouldShowFinalChatActions(
        conversation: Conversation?,
        isLoadingForCurrentConversation: Bool
    ) -> Bool {
        guard !isLoadingForCurrentConversation else { return false }
        guard let conversation else { return false }
        guard conversation.messages.contains(where: { $0.role == .assistant }) else { return false }
        guard let lastMessage = conversation.messages.last else { return false }
        return lastMessage.role == .assistant && !lastMessage.isStreaming
    }

    static func mergeReasoningText(existing: String?, incoming: String) -> String {
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty else {
            return ChatStore.sanitizedChatReasoningText(existing ?? "")
        }
        guard let existing, !existing.isEmpty else {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }

        if incomingTrimmed == existing { return ChatStore.sanitizedChatReasoningText(existing) }
        if incomingTrimmed.hasPrefix(existing) {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }
        if existing.hasPrefix(incomingTrimmed) || existing.contains(incomingTrimmed) {
            return ChatStore.sanitizedChatReasoningText(existing)
        }
        if incomingTrimmed.contains(existing) {
            return ChatStore.sanitizedChatReasoningText(String(incomingTrimmed.prefix(24_000)))
        }

        let overlap = reasoningSuffixPrefixOverlapLength(lhs: existing, rhs: incomingTrimmed)
        if overlap > 0 {
            let suffixStart = incomingTrimmed.index(incomingTrimmed.startIndex, offsetBy: overlap)
            let merged = existing + String(incomingTrimmed[suffixStart...])
            return ChatStore.sanitizedChatReasoningText(String(merged.suffix(24_000)))
        }

        // Chunk incrementali senza overlap: concatena senza `\n\n` (evita parole spezzate nello stream).
        let merged = existing + incomingTrimmed
        return ChatStore.sanitizedChatReasoningText(String(merged.suffix(24_000)))
    }

    internal static func reasoningSuffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        let maxOverlap = min(lhs.count, rhs.count, 1_024)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if lhs.suffix(size) == rhs.prefix(size) {
                return size
            }
        }
        return 0
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

    internal func clearPlanStreamingState() {
        flushPlanStreamingContent()
        if let targetConversationId = conversationId {
            planStreamingContentByConversation[targetConversationId] = ""
            planStreamingContent = ""
            if streaming.pendingPlanStreamConversationId == targetConversationId {
                streaming.pendingPlanStreamConversationId = nil
                streaming.pendingPlanStreamingContent = nil
            }
        } else {
            planStreamingContentByConversation.removeAll()
            planStreamingContent = ""
            streaming.pendingPlanStreamConversationId = nil
            streaming.pendingPlanStreamingContent = nil
        }
        streaming.planStreamThrottleTask?.cancel()
        streaming.planStreamThrottleTask = nil
    }

    internal func shouldRoutePlanStream(to conversationId: UUID?) -> Bool {
        let hasContext = hasActivePlanContext(for: conversationId)
        return shouldRoutePlanStreamToPlanPanel(
            shouldRoutePlanStreamingToPanel: shouldRoutePlanStreamingToPanel,
            streamConversationId: conversationId,
            hasActivePlanContext: hasContext,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
    }

    internal func updatePlanStreamingContent(_ content: String, conversationId: UUID?) {
        streaming.pendingPlanStreamConversationId = conversationId
        streaming.pendingPlanStreamingContent = content.count > 24_000
            ? String(content.suffix(24_000))
            : content

        // If a throttle is already scheduled, coalesce with latest text.
        if streaming.planStreamThrottleTask != nil { return }

        // Show first chunk without delay.
        flushPlanStreamingContent()

        // Coalesce and defer subsequent updates to reduce re-render churn.
        streaming.planStreamThrottleTask = Task {
            let delay = UInt64(planStreamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                flushPlanStreamingContent()
            }
        }
    }

    internal func appendPlanStreamingContent(_ content: String, conversationId: UUID?) {
        updatePlanStreamingContent(content, conversationId: conversationId)
    }

    internal func stripPlanCheckboxes(_ content: String) -> String {
        content.replacingOccurrences(
            of: #"(?m)^(\s*[-*]\s*)\[\s*[xX ]?\s*\]\s*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    internal func flushPlanStreamingContent() {
        streaming.planStreamThrottleTask?.cancel()
        streaming.planStreamThrottleTask = nil
        guard let newContent = streaming.pendingPlanStreamingContent else {
            if let currentConversationId = conversationId {
                planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
            }
            return
        }
        let targetConversationId = streaming.pendingPlanStreamConversationId
        streaming.pendingPlanStreamingContent = nil
        streaming.pendingPlanStreamConversationId = nil
        if let targetConversationId {
            planStreamingContentByConversation[targetConversationId] = newContent
        }
        if let currentConversationId = conversationId {
            planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
        } else if targetConversationId == nil {
            planStreamingContent = newContent
        }
    }

    // MARK: - Handle Stream Result (plan options + swarm delegation)

}
