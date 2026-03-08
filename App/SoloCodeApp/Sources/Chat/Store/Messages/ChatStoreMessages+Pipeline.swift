import Foundation

extension ChatStore {
    func updateAssistantMessagePipelineState(
        messageId: UUID,
        state: ChatTurnState,
        in conversationId: UUID,
        persistImmediately: Bool
    ) {
        mutateAssistantMessage(messageId: messageId, in: conversationId, persistImmediately: persistImmediately) { message in
            message.content = state.primaryTextSnapshot
            message.isStreaming = state.isStreaming
            message.primaryTextSnapshot = state.primaryTextSnapshot
            message.blocks = state.blocks
            message.turnMetadata = state.metadata
            message.reasoningText = state.reasoningTextSnapshot
        }
    }

    func syncLegacyAssistantContent(
        messageId: UUID,
        content: String,
        in conversationId: UUID?,
        persistImmediately: Bool
    ) {
        guard let conversationId else { return }
        let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
        mutateAssistantMessage(messageId: messageId, in: conversationId, persistImmediately: persistImmediately) { message in
            message.content = resolvedContent
            message.primaryTextSnapshot = resolvedContent
            var blocks = message.blocks ?? []
            if let idx = blocks.firstIndex(where: { $0.kind == .primaryText }) {
                blocks[idx].text = resolvedContent
            } else {
                blocks.insert(
                    PersistedChatTimelineBlock(
                        id: "primary-text",
                        kind: .primaryText,
                        text: resolvedContent
                    ),
                    at: 0
                )
            }
            message.blocks = blocks
        }
    }

    private func mutateAssistantMessage(
        messageId: UUID,
        in conversationId: UUID,
        persistImmediately: Bool,
        mutate: (inout ChatMessage) -> Void
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        guard let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
            $0.id == messageId && $0.role == .assistant
        }) else {
            return
        }

        var message = conversations[conversationIndex].messages[messageIndex]
        mutate(&message)
        conversations[conversationIndex].messages[messageIndex] = message

        if persistImmediately {
            saveConversations()
        } else {
            let now = Date()
            if now.timeIntervalSince(lastStreamingSaveAt) >= 3.0 {
                lastStreamingSaveAt = now
                saveConversations()
            }
        }
    }
}
