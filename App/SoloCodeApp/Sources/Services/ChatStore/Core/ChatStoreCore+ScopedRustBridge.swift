import Foundation

extension ChatStore {
    @MainActor
    func applyScopedRustBridgeConversations(
        _ updatedConversations: [Conversation],
        removingConversationIds: Set<UUID>
    ) {
        guard !updatedConversations.isEmpty || !removingConversationIds.isEmpty else { return }

        var nextConversations = conversations

        if !removingConversationIds.isEmpty {
            nextConversations.removeAll { removingConversationIds.contains($0.id) }
        }

        for updatedConversation in updatedConversations {
            if let index = nextConversations.firstIndex(where: { $0.id == updatedConversation.id }) {
                nextConversations[index] = updatedConversation
            } else {
                nextConversations.append(updatedConversation)
            }
        }

        conversations = nextConversations
    }
}
