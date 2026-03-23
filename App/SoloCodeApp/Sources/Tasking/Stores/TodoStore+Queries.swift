import Foundation

extension TodoStore {
    var visibleTodos: [TodoItem] {
        let filtered: [TodoItem]
        switch filter {
        case .open:
            filtered = todos.filter { $0.status != .done }
        case .inProgress:
            filtered = todos.filter { $0.status == .inProgress }
        case .completed:
            filtered = todos.filter { $0.status == .done }
        }

        return sortedCanonicalFirstTodos(filtered)
    }

    var completionRatio: Double {
        guard !todos.isEmpty else { return 0 }
        let done = Double(todos.filter { $0.status == .done }.count)
        return done / Double(todos.count)
    }

    var openTodosCount: Int {
        todos.filter { $0.status != .done }.count
    }

    var hasOpenTodos: Bool {
        openTodosCount > 0
    }

    func sortedCanonicalFirstTodos(_ items: [TodoItem]? = nil) -> [TodoItem] {
        (items ?? todos).sorted { lhs, rhs in
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
        let canonical = todos.filter(\.isPlanCanonical)
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

    /// Returns todos suitable for chat/task live cards, scoped STRICTLY to the current conversation.
    /// Prefer scoped todos, but preserve legacy fallback for unscoped runtime/tool todos.
    func displayTodosForChat(for conversationId: UUID?) -> [TodoItem] {
        guard let conversationId else {
            return sortedCanonicalFirstTodos()
        }

        let scoped = todos.filter { $0.planConversationId == conversationId }
        if !scoped.isEmpty {
            return sortedCanonicalFirstTodos(scoped)
        }
        let legacyUnscoped = todos.filter { $0.planConversationId == nil }
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
            guard !item.isPlanCanonical else { return false }
            return item.planConversationId == conversationId
        }
    }
}
