import Foundation
import CoderEngine

extension ChatStore {
    @MainActor
    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("set_streaming_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = streaming
        }
        if !applied {
            fallbackSetAssistantStreaming(conversationId: conversationId, streaming: streaming)
        }
        if !streaming {
            saveConversationsImmediately()
        } else {
            saveConversations()
        }
    }

    @MainActor
    func addMessage(_ message: ChatMessage, to conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("append_message") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied {
            fallbackAppendMessage(message, in: conversationId)
        } else {
            repairAppendMessageIfMissing(message, conversationId: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied {
            fallbackUpdateAssistantContent(conversationId: conversationId, content: resolvedContent)
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    func updateAssistantMessage(
        messageId: UUID,
        content: String,
        in conversationId: UUID?,
        persistImmediately: Bool = true
    ) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied {
            fallbackUpdateAssistantContent(
                conversationId: conversationId,
                messageId: messageId,
                content: resolvedContent
            )
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    func insertMessage(_ message: ChatMessage, before messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("insert_message_before") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied {
            fallbackInsertMessage(message, before: messageId, in: conversationId)
        } else {
            repairInsertMessageIfMissing(message, before: messageId, conversationId: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func removeTrailingEmptyAssistantMessages(in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("remove_trailing_empty_assistant_messages") { request in
            request.conversationId = conversationId.uuidString.lowercased()
        }
        if !applied {
            fallbackRemoveTrailingEmptyAssistantMessages(conversationId: conversationId)
        }
        saveConversationsImmediately()
    }

    @MainActor
    func fallbackAssistantMutationIndex(in conversation: Conversation) -> Int? {
        if let streamingIndex = conversation.messages.lastIndex(where: {
            $0.role == .assistant && $0.isStreaming
        }) {
            return streamingIndex
        }
        return conversation.messages.lastIndex(where: { $0.role == .assistant })
    }

    @MainActor
    func saveSubagentCardsToLastAssistant(_ cards: [SubagentCardSnapshot], in conversationId: UUID?) {
        guard !cards.isEmpty, let conversationId else { return }
        let applied = applyRustStoreAction("save_subagent_cards_to_last_assistant") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.subagentCards = cards.map(RustMainChatStoreAdapter.subagentCardSnapshot)
        }
        if !applied {
            NSLog("[ChatStore] save_subagent_cards_to_last_assistant failed for conv=%@", conversationId.uuidString)
            fallbackSaveSubagentCardsToLastAssistant(cards, conversationId: conversationId)
        }
        saveConversationsImmediately()
    }

    @MainActor
    func saveReasoningToLastAssistant(reasoning: String, in conversationId: UUID?) {
        guard let conversationId else { return }
        let trimmed = Self.sanitizedChatReasoningText(
            reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !trimmed.isEmpty else { return }
        let applied = applyRustStoreAction("save_reasoning") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = trimmed
        }
        if !applied {
            NSLog("[ChatStore] save_reasoning failed for conv=%@", conversationId.uuidString)
            fallbackSaveReasoningToLastAssistant(trimmed, conversationId: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func removeAssistantMessageIfEmpty(messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("remove_assistant_message_if_empty") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
        }
        if !applied {
            NSLog("[ChatStore] remove_assistant_message_if_empty failed for conv=%@ msg=%@", conversationId.uuidString, messageId.uuidString)
            fallbackRemoveAssistantMessageIfEmpty(messageId: messageId, conversationId: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func removeMessage(messageId: UUID, in conversationId: UUID?) {
        guard let conversationId else { return }
        let applied = applyRustStoreAction("remove_message") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
        }
        if !applied {
            NSLog("[ChatStore] remove_message failed for conv=%@ msg=%@", conversationId.uuidString, messageId.uuidString)
            fallbackRemoveMessage(messageId: messageId, conversationId: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func beginTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("begin_task") { request in
            request.conversationId = id.uuidString.lowercased()
            request.startedAt = Date()
        }
    }

    @MainActor
    func beginTask() {
        beginTask(conversationId: activeTaskConversationId)
    }

    @MainActor
    func endTask(conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("end_task") { request in
            request.conversationId = id.uuidString.lowercased()
        }
    }

    @MainActor
    func setTaskStatus(_ text: String, for conversationId: UUID?) {
        guard let id = conversationId else { return }
        requireRustTaskRuntime("set_task_status") { request in
            request.conversationId = id.uuidString.lowercased()
            request.statusText = text
        }
    }

    @MainActor
    func endTask() {
        endTask(conversationId: activeTaskConversationId)
    }

    @MainActor
    func updateAssistantMessagePipelineState(
        messageId: UUID,
        state: ChatTurnState,
        in conversationId: UUID,
        persistImmediately: Bool
    ) {
        if mainChatTraceLoggingEnabled() {
            NSLog(
                "[MainChatTrace] store sync_assistant_pipeline_state conv=%@ msg=%@ primary=%ld blocks=%ld streaming=%@",
                conversationId.uuidString.lowercased(),
                messageId.uuidString.lowercased(),
                state.primaryTextSnapshot.count,
                state.blocks.count,
                state.isStreaming ? "true" : "false"
            )
        }
        var pipelineMessage = ChatMessage(
            id: messageId,
            role: .assistant,
            content: state.primaryTextSnapshot,
            primaryTextSnapshot: state.primaryTextSnapshot,
            blocks: state.blocks,
            turnMetadata: state.metadata,
            isStreaming: state.isStreaming
        )
        pipelineMessage.reasoningText = state.reasoningTextSnapshot
        let applied = applyRustStoreAction("sync_assistant_pipeline_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(pipelineMessage)
        }
        if mainChatTraceLoggingEnabled() {
            NSLog(
                "[MainChatTrace] store sync_assistant_pipeline_state applied=%@ conv=%@ msg=%@",
                applied ? "true" : "false",
                conversationId.uuidString.lowercased(),
                messageId.uuidString.lowercased()
            )
        }
        if !applied,
           let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
           let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[convIdx].messages[msgIdx] = pipelineMessage
        }
        persistAssistantMutation(immediately: persistImmediately)
    }

    @MainActor
    func persistAssistantMutation(immediately: Bool) {
        if immediately {
            saveConversations()
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastStreamingSaveAt) >= 3.0 {
            lastStreamingSaveAt = now
            saveConversations()
        }
    }
}
