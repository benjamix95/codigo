import Foundation

/// Regole condivise tra card chat, composer e filtri (es. review auto-todo) per evitare drift.
/// Con più thread con `planConversationId` diversi, un runtime agent **senza** touch non compare in legacy
/// su tutte le chat: resta ancorato alla conversazione con UUID minimo (deterministico, una sola card).
enum TodoChatDisplayPolicy {
    /// Allinea a `TodoStore.displayTodosForChat` per `conversationId` non nil.
    static func itemAppearsInChat(_ item: TodoItem, conversationId: UUID, visibleTodos: [TodoItem]) -> Bool {
        let planScopeIds = Set(visibleTodos.compactMap(\.planConversationId))
        return itemAppearsInChat(
            item,
            conversationId: conversationId,
            visibleTodos: visibleTodos,
            planScopeIds: planScopeIds
        )
    }

    /// `planScopeIds` va calcolato una sola volta per snapshot (`Set(visibleTodos.compactMap(\.planConversationId))`).
    static func itemAppearsInChat(
        _ item: TodoItem,
        conversationId: UUID,
        visibleTodos: [TodoItem],
        planScopeIds: Set<UUID>
    ) -> Bool {
        guard !item.isOperationalPlaceholder else { return false }
        let scoped = visibleTodos.filter { $0.planConversationId == conversationId }
        let legacyMatch =
            item.planConversationId == nil
            && includeInLegacyUnscopedBucket(item, conversationId: conversationId, planScopeIds: planScopeIds)
        if !scoped.isEmpty {
            return item.planConversationId == conversationId || legacyMatch
        }
        let hasForeignScopedWork = planScopeIds.contains { $0 != conversationId }
        if hasForeignScopedWork { return false }
        return legacyMatch
    }

    private static func includeInLegacyUnscopedBucket(
        _ item: TodoItem,
        conversationId: UUID,
        planScopeIds: Set<UUID>
    ) -> Bool {
        if item.source == .agent, !item.isPlanCanonical, !item.isOperationalPlaceholder {
            if let touch = item.lastTouchedConversationId {
                return touch == conversationId
            }
            if planScopeIds.isEmpty {
                return true
            }
            if planScopeIds.count >= 2 {
                guard let anchor = planScopeIds.min(by: { $0.uuidString < $1.uuidString }) else {
                    return true
                }
                return conversationId == anchor
            }
            return planScopeIds.count == 1 && planScopeIds.contains(conversationId)
        }
        return true
    }
}
