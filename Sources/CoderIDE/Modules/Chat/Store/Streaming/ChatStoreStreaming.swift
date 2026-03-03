import Foundation
import CoderEngine

extension ChatStore {
func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
    guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
    guard let lastIdx = targetAssistantMessageIndex(conversationIndex: idx) else { return }
    var conv = conversations[idx]
    var msgs = conv.messages
    var msg = msgs[lastIdx]
    msg.isStreaming = streaming
    msgs[lastIdx] = msg
    conv.messages = msgs
    var updated = conversations
    updated[idx] = conv
    conversations = updated
    if !streaming {
        saveConversationsImmediately()
    } else {
        saveConversations()
    }
}

func beginTask(conversationId: UUID?) {
    guard let id = conversationId else { return }
    activeTaskConversationIds.insert(id)
    taskStartDates[id] = Date()
    taskStatusTexts[id] = "Thinking"
}

// Legacy call site compatibility.
func beginTask() {
    beginTask(conversationId: activeTaskConversationId)
}

func endTask(conversationId: UUID?) {
    guard let id = conversationId else { return }
    activeTaskConversationIds.remove(id)
    taskStartDates.removeValue(forKey: id)
    taskStatusTexts.removeValue(forKey: id)
}

func setTaskStatus(_ text: String, for conversationId: UUID?) {
    guard let id = conversationId else { return }
    taskStatusTexts[id] = text
}

// Compat legacy call sites.
func endTask() {
    endTask(conversationId: activeTaskConversationId)
}
}
