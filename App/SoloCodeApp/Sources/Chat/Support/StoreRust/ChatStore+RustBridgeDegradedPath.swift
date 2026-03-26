import Foundation
import CoderEngine

extension ChatStore {
    /// Ripara timeline quando il reducer Rust segnala successo ma il messaggio non compare.
    @MainActor
    func repairAppendMessageIfMissing(_ message: ChatMessage, conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if conversations[idx].messages.contains(where: { $0.id == message.id }) { return }
        fallbackAppendMessage(message, in: conversationId)
    }

    @MainActor
    func repairInsertMessageIfMissing(
        _ message: ChatMessage,
        before anchorId: UUID,
        conversationId: UUID
    ) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if conversations[idx].messages.contains(where: { $0.id == message.id }) { return }
        fallbackInsertMessage(message, before: anchorId, in: conversationId)
    }

    @MainActor
    func fallbackSaveSubagentCardsToLastAssistant(_ cards: [SubagentCardSnapshot], conversationId: UUID) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIdx = fallbackAssistantMutationIndex(in: conversations[convIdx])
        else { return }
        var msg = conversations[convIdx].messages[msgIdx]
        msg.subagentCards = cards
        conversations[convIdx].messages[msgIdx] = msg
    }

    @MainActor
    func fallbackSaveReasoningToLastAssistant(_ text: String, conversationId: UUID) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIdx = fallbackAssistantMutationIndex(in: conversations[convIdx])
        else { return }
        var msg = conversations[convIdx].messages[msgIdx]
        msg.reasoningText = text
        conversations[convIdx].messages[msgIdx] = msg
    }

    @MainActor
    func fallbackRemoveAssistantMessageIfEmpty(messageId: UUID, conversationId: UUID) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        let msg = conversations[convIdx].messages[msgIdx]
        guard msg.role == .assistant,
              msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        conversations[convIdx].messages.remove(at: msgIdx)
    }

    @MainActor
    func fallbackRemoveMessage(messageId: UUID, conversationId: UUID) {
        guard let convIdx = conversations.firstIndex(where: { $0.id == conversationId }),
              let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageId })
        else { return }
        conversations[convIdx].messages.remove(at: msgIdx)
    }

    @MainActor
    func fallbackRemoveTrailingEmptyAssistantMessages(conversationId: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == conversationId }) else {
            return
        }
        while let last = conversations[conversationIndex].messages.last,
              last.role == .assistant,
              !last.isStreaming,
              last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            conversations[conversationIndex].messages.removeLast()
        }
    }
}
