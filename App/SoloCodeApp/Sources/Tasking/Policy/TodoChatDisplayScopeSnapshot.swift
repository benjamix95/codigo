import Foundation

struct TodoChatDisplayScopeSnapshot {
    let planScopeIds: Set<UUID>
    let scopedConversationIds: Set<UUID>
    let legacyAnchorConversationId: UUID?

    init(visibleTodos: [TodoItem]) {
        let scopeIds = Set(visibleTodos.compactMap(\.planConversationId))
        planScopeIds = scopeIds
        scopedConversationIds = scopeIds
        legacyAnchorConversationId = scopeIds.min { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    func hasScopedItems(for conversationId: UUID) -> Bool {
        scopedConversationIds.contains(conversationId)
    }

    func hasForeignScopedWork(for conversationId: UUID) -> Bool {
        planScopeIds.contains { $0 != conversationId }
    }
}
