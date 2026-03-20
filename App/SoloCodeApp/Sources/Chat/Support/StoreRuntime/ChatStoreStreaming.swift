import Foundation
import CoderEngine

extension ChatStore {
func setLastAssistantStreaming(_ streaming: Bool, in conversationId: UUID?) {
    guard let conversationId else { return }
    _ = applyRustStoreAction("set_streaming_state") { request in
        request.conversationId = conversationId.uuidString.lowercased()
        request.boolValue = streaming
    }
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
