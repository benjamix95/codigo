import Foundation

/// Regole condivise tra card chat, composer e filtri (es. review auto-todo) per evitare drift.
/// L’insieme `itemAppearsInChat` coincide con `TodoStore.displayTodosForChat` (filtrato per `conversationId` non nil).
enum TodoChatDisplayPolicy {
    /// Allinea a `TodoStore.displayTodosForChat`: stesso insieme di todo visibili per `conversationId`.
    static func itemAppearsInChat(_ item: TodoItem, conversationId: UUID, visibleTodos: [TodoItem]) -> Bool {
        guard !item.isOperationalPlaceholder else { return false }
        let scoped = visibleTodos.filter { $0.planConversationId == conversationId }
        let legacyMatch =
            item.planConversationId == nil && includeInLegacyUnscopedBucket(item, conversationId: conversationId)
        if !scoped.isEmpty {
            return item.planConversationId == conversationId || legacyMatch
        }
        let hasForeignScopedWork = visibleTodos.contains { row in
            guard let sid = row.planConversationId else { return false }
            return sid != conversationId
        }
        if hasForeignScopedWork { return false }
        return legacyMatch
    }

    private static func includeInLegacyUnscopedBucket(_ item: TodoItem, conversationId: UUID) -> Bool {
        if item.source == .agent, !item.isPlanCanonical, !item.isOperationalPlaceholder {
            if let touch = item.lastTouchedConversationId {
                return touch == conversationId
            }
            return true
        }
        return true
    }
}
