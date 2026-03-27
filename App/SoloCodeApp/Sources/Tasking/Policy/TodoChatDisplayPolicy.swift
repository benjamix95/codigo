import Foundation

/// Regole condivise tra card chat, composer e filtri (es. review auto-todo) per evitare drift.
/// Con più thread con `planConversationId` diversi, un runtime agent **senza** touch non compare in legacy
/// su tutte le chat: resta ancorato alla conversazione con UUID minimo (deterministico, una sola card).
enum TodoChatDisplayPolicy {
    /// Allinea a `TodoStore.displayTodosForChat` per `conversationId` non nil.
    static func itemAppearsInChat(_ item: TodoItem, conversationId: UUID, visibleTodos: [TodoItem]) -> Bool {
        let scopeSnapshot = TodoChatDisplayScopeSnapshot(visibleTodos: visibleTodos)
        return itemAppearsInChat(
            item,
            conversationId: conversationId,
            scopeSnapshot: scopeSnapshot
        )
    }

    static func itemAppearsInChat(
        _ item: TodoItem,
        conversationId: UUID,
        scopeSnapshot: TodoChatDisplayScopeSnapshot
    ) -> Bool {
        guard !item.isOperationalPlaceholder else { return false }
        let legacyMatch =
            item.planConversationId == nil
            && includeInLegacyUnscopedBucket(
                item,
                conversationId: conversationId,
                scopeSnapshot: scopeSnapshot
            )
        if scopeSnapshot.hasScopedItems(for: conversationId) {
            return item.planConversationId == conversationId || legacyMatch
        }
        if scopeSnapshot.hasForeignScopedWork(for: conversationId) { return false }
        return legacyMatch
    }

    private static func includeInLegacyUnscopedBucket(
        _ item: TodoItem,
        conversationId: UUID,
        scopeSnapshot: TodoChatDisplayScopeSnapshot
    ) -> Bool {
        if item.source == .agent, !item.isPlanCanonical, !item.isOperationalPlaceholder {
            if let touch = item.lastTouchedConversationId {
                return touch == conversationId
            }
            if scopeSnapshot.planScopeIds.isEmpty {
                return true
            }
            if scopeSnapshot.planScopeIds.count >= 2 {
                guard let anchor = scopeSnapshot.legacyAnchorConversationId else {
                    return true
                }
                return conversationId == anchor
            }
            return scopeSnapshot.planScopeIds.count == 1
                && scopeSnapshot.planScopeIds.contains(conversationId)
        }
        return true
    }
}
