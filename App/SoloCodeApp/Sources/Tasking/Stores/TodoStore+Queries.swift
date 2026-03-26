import Foundation

extension TodoStore {
    var userVisibleTodos: [TodoItem] {
        todos.filter { !$0.isOperationalPlaceholder }
    }

    var visibleTodos: [TodoItem] {
        let filtered: [TodoItem]
        switch filter {
        case .open:
            filtered = userVisibleTodos.filter { $0.status != .done }
        case .inProgress:
            filtered = userVisibleTodos.filter { $0.status == .inProgress }
        case .completed:
            filtered = userVisibleTodos.filter { $0.status == .done }
        }

        return sortedCanonicalFirstTodos(filtered)
    }

    var completionRatio: Double {
        let visible = userVisibleTodos
        guard !visible.isEmpty else { return 0 }
        let done = Double(visible.filter { $0.status == .done }.count)
        return done / Double(visible.count)
    }

    var openTodosCount: Int {
        userVisibleTodos.filter { $0.status != .done }.count
    }

    var hasOpenTodos: Bool {
        openTodosCount > 0
    }

    func sortedCanonicalFirstTodos(_ items: [TodoItem]? = nil) -> [TodoItem] {
        (items ?? userVisibleTodos).filter { !$0.isOperationalPlaceholder }.sorted { lhs, rhs in
            if lhs.isPlanCanonical != rhs.isPlanCanonical { return lhs.isPlanCanonical }
            if lhs.isPlanCanonical, rhs.isPlanCanonical {
                let lhsScope = lhs.planConversationId?.uuidString ?? ""
                let rhsScope = rhs.planConversationId?.uuidString ?? ""
                if lhsScope != rhsScope { return lhsScope < rhsScope }

                let lhsOrder = lhs.planOrder ?? Int.max
                let rhsOrder = rhs.planOrder ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            }
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func canonicalTodos(for conversationId: UUID?) -> [TodoItem] {
        let canonical = userVisibleTodos.filter(\.isPlanCanonical)
        guard let conversationId else {
            return sortedCanonicalFirstTodos(canonical)
        }
        let scoped = canonical.filter { $0.planConversationId == conversationId }
        if !scoped.isEmpty {
            return sortedCanonicalFirstTodos(scoped)
        }
        let legacyUnscoped = canonical.filter { $0.planConversationId == nil }
        return sortedCanonicalFirstTodos(legacyUnscoped)
    }

    /// Returns todos suitable for chat/task live cards.
    /// - Merges conversation-scoped items with legacy unscoped (`planConversationId == nil`) so runtime
    ///   tasks without scope still appear alongside scoped work in the same chat.
    /// - When this conversation has no scoped items, falls back to all unscoped todos (legacy Codex/agent paths).
    func displayTodosForChat(for conversationId: UUID?) -> [TodoItem] {
        let visible = userVisibleTodos
        guard let conversationId else {
            return sortedCanonicalFirstTodos(visible)
        }

        let scoped = visible.filter { $0.planConversationId == conversationId }
        let legacyUnscoped = visible.filter { $0.planConversationId == nil }
        if !scoped.isEmpty {
            return sortedCanonicalFirstTodos(scoped + legacyUnscoped)
        }
        return sortedCanonicalFirstTodos(legacyUnscoped)
    }

    func canonicalScopeFilter(for conversationId: UUID?) -> (TodoItem) -> Bool {
        guard let conversationId else {
            return { $0.isPlanCanonical }
        }
        let hasScoped = todos.contains { $0.isPlanCanonical && $0.planConversationId == conversationId }
        return { item in
            guard item.isPlanCanonical else { return false }
            if let scopedConversation = item.planConversationId {
                return scopedConversation == conversationId
            }
            return !hasScoped
        }
    }

    func runtimeScopeFilter(for conversationId: UUID?) -> (TodoItem) -> Bool {
        guard let conversationId else {
            return { !$0.isPlanCanonical }
        }
        // Strict scoping: only show runtime todos that belong to this conversation.
        // No legacy fallback — unscoped todos from other conversations stay hidden.
        return { item in
            guard !item.isPlanCanonical, !item.isOperationalPlaceholder else { return false }
            return item.planConversationId == conversationId
        }
    }
}
