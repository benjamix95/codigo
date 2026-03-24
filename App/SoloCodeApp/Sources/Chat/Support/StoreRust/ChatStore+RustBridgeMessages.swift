import Foundation
import CoderEngine

extension ChatStore {
    @MainActor
    func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
        guard let conversationId else { return }
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("set_streaming_state") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.boolValue = streaming
        }
        if !applied, allowLocalFallback {
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
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("append_message") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied, allowLocalFallback {
            fallbackAppendMessage(message, in: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied, allowLocalFallback {
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
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("sync_assistant_content") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.text = resolvedContent
        }
        if !applied, allowLocalFallback {
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
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
        let applied = applyRustStoreAction("insert_message_before") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.messageId = messageId.uuidString.lowercased()
            request.message = RustMainChatStoreAdapter.messageSnapshot(message)
        }
        if !applied, allowLocalFallback {
            fallbackInsertMessage(message, before: messageId, in: conversationId)
        }
        saveConversations()
    }

    @MainActor
    func removeTrailingEmptyAssistantMessages(in conversationId: UUID?) {
        guard let conversationId else { return }
        if shouldSkipRustStoreBootstrapForTests(environment: ProcessInfo.processInfo.environment),
           let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) {
            while let last = conversations[conversationIndex].messages.last,
                  last.role == .assistant,
                  !last.isStreaming,
                  last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                conversations[conversationIndex].messages.removeLast()
            }
        } else {
            _ = applyRustStoreAction("remove_trailing_empty_assistant_messages") { request in
                request.conversationId = conversationId.uuidString.lowercased()
            }
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
        }
        saveConversationsImmediately()
    }

    @MainActor
    func saveReasoningToLastAssistant(reasoning: String, in conversationId: UUID?) {
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let conversationId else { return }
        let applied = applyRustStoreAction("save_reasoning") { request in
            request.conversationId = conversationId.uuidString.lowercased()
            request.text = trimmed
        }
        if !applied {
            NSLog("[ChatStore] save_reasoning failed for conv=%@", conversationId.uuidString)
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
        let allowLocalFallback = shouldSkipRustStoreBootstrapForTests(
            environment: ProcessInfo.processInfo.environment
        )
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
        if !applied, allowLocalFallback,
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
