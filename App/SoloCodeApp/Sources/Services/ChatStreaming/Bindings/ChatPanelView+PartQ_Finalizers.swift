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
    internal func applyMainChatUIStreamIntent(
        _ intent: String,
        conversationId targetConversationId: UUID?,
        providerId: String?,
        text: String? = nil,
        payload: [String: String] = [:]
    ) {
        let state = RustMainChatStoreAdapter.uiState(
            from: chatStore,
            runtimeSnapshot: flowCoordinator.directRuntimeSnapshotState() ?? flowCoordinator.planRuntimeSnapshotState(),
            selectedConversationId: targetConversationId ?? conversationId,
            draftText: inputText,
            planPanelVisible: showPlanPanel,
            followLive: isFollowingLive,
            collapsedArtifactsByTurn: collapsedArtifactsByTurn
        )
        let requestPayload = (providerId.map { ["provider_id": $0] } ?? [:]).merging(payload) {
            _, new in new
        }
        let request = MainChatUIIntentRequestBridge(
            schemaVersion: 1,
            intent: intent,
            state: state,
            conversationId: targetConversationId?.uuidString.lowercased(),
            turnId: nil,
            artifactId: nil,
            text: text,
            timestamp: Date(),
            payload: requestPayload
        )
        let applied = RustMainChatStoreAdapter.applyUIIntent(request, to: chatStore) != nil
        if applied {
            streamContentVersion &+= 1
        }
        // Fallback: if the Rust UI intent didn't apply, or applied but the
        // message content is still empty, update content directly so that
        // message text always appears inline in the chat.
        if intent == "stream_replace_text",
           let text,
           !text.isEmpty,
           let targetConversationId,
           let targetMessageId = currentAssistantPipelineTarget(for: targetConversationId)?.messageId
        {
            let currentContent = chatStore.conversation(for: targetConversationId)?
                .messages.first(where: { $0.id == targetMessageId })?
                .content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !applied || currentContent.isEmpty {
                chatStore.updateAssistantMessage(
                    messageId: targetMessageId,
                    content: text,
                    in: targetConversationId,
                    persistImmediately: false
                )
                if !applied { streamContentVersion &+= 1 }
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
            streamContentVersion &+= 1
        }
    }

    internal func discardPendingStreamingState(for targetConversationId: UUID?) {
        streamThrottleTask?.cancel()
        streamThrottleTask = nil
        if shouldDiscardPendingStreamSnapshot(
            targetConversationId: targetConversationId,
            pendingConversationId: pendingStreamConversationId
        ) {
            pendingStreamContent = nil
            pendingStreamConversationId = nil
            streamingSegments.removeAll()
        }
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
        if let targetConversationId,
           pendingPlanStreamConversationId == targetConversationId {
            pendingPlanStreamingContent = nil
            pendingPlanStreamConversationId = nil
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
        guard !incomingTrimmed.isEmpty else { return existing ?? "" }
        guard let existing, !existing.isEmpty else {
            return String(incoming.prefix(24_000))
        }

        if incoming == existing { return existing }
        if incoming.hasPrefix(existing) {
            return String(incoming.prefix(24_000))
        }
        if existing.hasPrefix(incoming) || existing.contains(incoming) {
            return existing
        }
        if incoming.contains(existing) {
            return String(incoming.prefix(24_000))
        }

        let overlap = reasoningSuffixPrefixOverlapLength(lhs: existing, rhs: incoming)
        if overlap > 0 {
            let suffixStart = incoming.index(incoming.startIndex, offsetBy: overlap)
            let merged = existing + String(incoming[suffixStart...])
            return String(merged.suffix(24_000))
        }

        let separator =
            existing.hasSuffix("\n") || incoming.hasPrefix("\n")
            ? "\n"
            : "\n\n"
        let merged = existing + separator + incoming
        return String(merged.suffix(24_000))
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
        let hadInlineReasoning = streamingReasoningConversationId == id
        let hasSeparateThinkingMessages =
            !(reasoningMessageIdByConversationAndGroup[id]?.isEmpty ?? true)
        if hadInlineReasoning,
           !hasSeparateThinkingMessages,
           let reasoning = streamingReasoningText,
           !reasoning.isEmpty
        {
            chatStore.saveReasoningToLastAssistant(reasoning: reasoning, in: id)
        }
        resetReasoningMessageState(for: id)
        codexLastReasoningLine = nil
        chatStore.removeTrailingEmptyAssistantMessages(in: id)
        if hadInlineReasoning || hasSeparateThinkingMessages {
            streamingReasoningText = nil
            streamingReasoningConversationId = nil
            streamingReasoningBlocks = []
            streamingSegments = []
            streamingSegmentTurnIndex = 0
        }
    }

    internal func clearPlanStreamingState() {
        flushPlanStreamingContent()
        if let targetConversationId = conversationId {
            planStreamingContentByConversation[targetConversationId] = ""
            planStreamingContent = ""
            if pendingPlanStreamConversationId == targetConversationId {
                pendingPlanStreamConversationId = nil
                pendingPlanStreamingContent = nil
            }
        } else {
            planStreamingContentByConversation.removeAll()
            planStreamingContent = ""
            pendingPlanStreamConversationId = nil
            pendingPlanStreamingContent = nil
        }
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
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
        pendingPlanStreamConversationId = conversationId
        pendingPlanStreamingContent = content.count > 24_000
            ? String(content.suffix(24_000))
            : content

        // If a throttle is already scheduled, coalesce with latest text.
        if planStreamThrottleTask != nil { return }

        // Show first chunk without delay.
        flushPlanStreamingContent()

        // Coalesce and defer subsequent updates to reduce re-render churn.
        planStreamThrottleTask = Task {
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
        planStreamThrottleTask?.cancel()
        planStreamThrottleTask = nil
        guard let newContent = pendingPlanStreamingContent else {
            if let currentConversationId = conversationId {
                planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
            }
            return
        }
        let targetConversationId = pendingPlanStreamConversationId
        pendingPlanStreamingContent = nil
        pendingPlanStreamConversationId = nil
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

