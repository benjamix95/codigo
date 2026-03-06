import Foundation
import CoderEngine

extension ChatStore {
/// Sets isStreaming=false on all assistant messages. Call before adding
/// a new assistant placeholder to avoid duplicate loading indicators.
func clearStaleAssistantStreaming(conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    var conv = conversations[idx]
    var msgs = conv.messages
    var changed = false
    for i in msgs.indices where msgs[i].role == .assistant {
        if msgs[i].isStreaming {
            msgs[i].isStreaming = false
            changed = true
        }
    }
    if changed {
        conv.messages = msgs
        conversations[idx] = conv
        saveConversations()
    }
}

func addMessage(_ message: ChatMessage, to conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    if message.role == .assistant, message.isStreaming {
        clearStaleAssistantStreaming(conversationId: conversationId)
    }
    conversations[idx].messages.append(message)
    if conversations[idx].title == "New conversation", case .user = message.role {
        conversations[idx].title = String(message.content.prefix(40))
        if message.content.count > 40 { conversations[idx].title += "…" }
    }
    saveConversations()
}

func targetAssistantMessageIndex(conversationIndex: Int) -> Int? {
    if let streamingIdx = conversations[conversationIndex].messages.lastIndex(where: {
        $0.role == .assistant && $0.isStreaming
    }) {
        return streamingIdx
    }
    return conversations[conversationIndex].messages.lastIndex(where: { $0.role == .assistant })
}

/// - Parameter persistImmediately: if false, skips saveConversations but still
///   triggers a safety save every ~3 seconds to prevent data loss during long streams.
func updateLastAssistantMessage(content: String, in conversationId: UUID?, persistImmediately: Bool = true) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let lastIdx = targetAssistantMessageIndex(conversationIndex: idx) else { return }
    let targetMessageId = conversations[idx].messages[lastIdx].id
    let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
    if conversations[idx].messages[lastIdx].content == resolvedContent,
       conversations[idx].messages[lastIdx].primaryTextSnapshot == resolvedContent {
        return
    }
    syncLegacyAssistantContent(
        messageId: targetMessageId,
        content: resolvedContent,
        in: conversationId,
        persistImmediately: persistImmediately
    )
}

func updateAssistantMessage(
    messageId: UUID,
    content: String,
    in conversationId: UUID?,
    persistImmediately: Bool = true
) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let messageIdx = conversations[idx].messages.firstIndex(where: {
        $0.id == messageId && $0.role == .assistant
    }) else { return }
    let resolvedContent = Self.stripCoderideMarkers(content, aggressive: false)
    if conversations[idx].messages[messageIdx].content == resolvedContent,
       conversations[idx].messages[messageIdx].primaryTextSnapshot == resolvedContent {
        return
    }
    syncLegacyAssistantContent(
        messageId: messageId,
        content: resolvedContent,
        in: conversationId,
        persistImmediately: persistImmediately
    )
}

func insertMessage(_ message: ChatMessage, before messageId: UUID, in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    if message.role == .assistant, message.isStreaming {
        clearStaleAssistantStreaming(conversationId: conversationId)
    }
    if let anchorIdx = conversations[idx].messages.firstIndex(where: { $0.id == messageId }) {
        conversations[idx].messages.insert(message, at: anchorIdx)
    } else {
        conversations[idx].messages.append(message)
    }
    if conversations[idx].title == "New conversation", case .user = message.role {
        conversations[idx].title = String(message.content.prefix(40))
        if message.content.count > 40 { conversations[idx].title += "…" }
    }
    saveConversations()
}

func removeTrailingEmptyAssistantMessages(in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    while let last = conversations[idx].messages.last,
          last.role == .assistant,
          last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !last.isStreaming
    {
        conversations[idx].messages.removeLast()
    }
}

func saveSubagentCardsToLastAssistant(_ cards: [SubagentCardSnapshot], in conversationId: UUID?) {
    guard !cards.isEmpty else { return }
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else {
        NSLog("[ChatStore] saveSubagentCardsToLastAssistant: conversation %@ not found — %d card(s) lost", conversationId?.uuidString ?? "nil", cards.count)
        return
    }
    if let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) {
        conversations[idx].messages[lastIdx].subagentCards = cards
    } else {
        NSLog("[ChatStore] saveSubagentCardsToLastAssistant: no assistant message in %@ — creating placeholder to preserve %d card(s)", conversationId?.uuidString ?? "?", cards.count)
        var placeholder = ChatMessage(role: .assistant, content: "")
        placeholder.subagentCards = cards
        conversations[idx].messages.append(placeholder)
    }
    saveConversationsImmediately()
}

func saveReasoningToLastAssistant(reasoning: String, in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let lastIdx = conversations[idx].messages.lastIndex(where: { $0.role == .assistant }) else { return }
    let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    conversations[idx].messages[lastIdx].reasoningText = trimmed
    var blocks = conversations[idx].messages[lastIdx].blocks ?? []
    if let reasoningIdx = blocks.firstIndex(where: { $0.kind == .reasoning }) {
        blocks[reasoningIdx].text = trimmed
    } else {
        blocks.append(
            PersistedChatTimelineBlock(
                id: "reasoning",
                kind: .reasoning,
                title: "Thinking",
                text: trimmed,
                isCollapsible: true,
                isCollapsedByDefault: true
            )
        )
    }
    conversations[idx].messages[lastIdx].blocks = blocks
    saveConversations()
}

func removeAssistantMessageIfEmpty(messageId: UUID, in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let midx = conversations[idx].messages.firstIndex(where: { $0.id == messageId }) else {
        return
    }
    let message = conversations[idx].messages[midx]
    guard message.role == .assistant else { return }
    let trimmed = message.resolvedPrimaryText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty else { return }
    removeMessage(messageId: messageId, in: conversationId)
}

func removeMessage(messageId: UUID, in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let midx = conversations[idx].messages.firstIndex(where: { $0.id == messageId }) else {
        return
    }
    conversations[idx].messages.remove(at: midx)
    conversations[idx].checkpoints.removeAll { $0.messageCount > conversations[idx].messages.count }
    saveConversations()
}
}
