import Foundation

extension TodoStore {
    var userVisibleTodos: [TodoItem] {
        cachedUserVisibleTodos()
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
        let filtered = (items ?? userVisibleTodos).filter { !$0.isOperationalPlaceholder }
        let canonical = filtered.filter(\.isPlanCanonical).sorted { lhs, rhs in
            let lhsScope = lhs.planConversationId?.uuidString ?? ""
            let rhsScope = rhs.planConversationId?.uuidString ?? ""
            if lhsScope != rhsScope { return lhsScope < rhsScope }

            let lhsOrder = lhs.planOrder ?? Int.max
            let rhsOrder = rhs.planOrder ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.createdAt < rhs.createdAt
        }
        let runtime = orderedRuntimeExecutionTodos(filtered.filter { !$0.isPlanCanonical })
        return canonical + runtime
    }

    func cachedTodoChatDisplayScopeSnapshot() -> TodoChatDisplayScopeSnapshot {
        if let cached = todoChatDisplayScopeCache {
            return cached
        }
        let snapshot = TodoChatDisplayScopeSnapshot(visibleTodos: userVisibleTodos)
        todoChatDisplayScopeCache = snapshot
        return snapshot
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
        let hasScopedCanonicalElsewhere = canonical.contains { $0.planConversationId != nil }
        guard !hasScopedCanonicalElsewhere else {
            return []
        }
        let legacyUnscoped = canonical.filter { $0.planConversationId == nil }
        return sortedCanonicalFirstTodos(legacyUnscoped)
    }

    /// Returns todos suitable for chat/task live cards.
    /// - Merges conversation-scoped items with legacy unscoped (`planConversationId == nil`) so runtime
    ///   tasks without scope still appear alongside scoped work in the same chat.
    /// - Con fallback unscoped solo se nessun altro thread ha todo con scope (`planConversationId` non-nil),
    ///   per evitare di mostrare la stessa coda “orfana” in chat che non sono la sorgente del lavoro scoped.
    func displayTodosForChat(for conversationId: UUID?) -> [TodoItem] {
        let cacheKey = cachedDisplayTodosKey(for: conversationId)
        if let cached = displayTodosCacheByConversationKey[cacheKey] {
            return cached
        }
        let visible = userVisibleTodos
        let resolved: [TodoItem]
        guard let conversationId else {
            resolved = sortedCanonicalFirstTodos(visible)
            displayTodosCacheByConversationKey[cacheKey] = resolved
            return resolved
        }
        let scopeSnapshot = cachedTodoChatDisplayScopeSnapshot()
        let inChat = visible.filter {
            TodoChatDisplayPolicy.itemAppearsInChat(
                $0,
                conversationId: conversationId,
                scopeSnapshot: scopeSnapshot
            )
        }
        resolved = sortedCanonicalFirstTodos(inChat)
        displayTodosCacheByConversationKey[cacheKey] = resolved
        return resolved
    }

    /// Composer durante Plan: include todo operativi (placeholder) ancorati al thread.
    func displayTodosForComposer(
        for conversationId: UUID,
        includeOperationalRuntimeTodos: Bool
    ) -> [TodoItem] {
        if includeOperationalRuntimeTodos {
            return displayPlanScopedTodos(
                for: conversationId,
                includeOperationalPlaceholders: true
            )
        }
        return displayTodosForChat(for: conversationId)
    }

    func displayPlanScopedTodos(
        for conversationId: UUID?,
        includeOperationalPlaceholders: Bool
    ) -> [TodoItem] {
        let canonical = canonicalTodos(for: conversationId)
        guard includeOperationalPlaceholders, let conversationId else {
            return canonical
        }

        let ops = todos.filter {
            $0.isOperationalPlaceholder
                && $0.status != .done
                && $0.planConversationId == conversationId
        }
        let existing = Set(canonical.map(\.id))
        let merged = canonical + ops.filter { !existing.contains($0.id) }
        return merged.sorted { lhs, rhs in
            if lhs.isPlanCanonical != rhs.isPlanCanonical { return lhs.isPlanCanonical && !rhs.isPlanCanonical }
            let lo = lhs.planOrder ?? Int.max
            let ro = rhs.planOrder ?? Int.max
            if lo != ro { return lo < ro }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
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
        let scopeSnapshot = cachedTodoChatDisplayScopeSnapshot()
        return { item in
            guard !item.isPlanCanonical, !item.isOperationalPlaceholder else { return false }
            if item.planConversationId == conversationId { return true }
            if item.planConversationId == nil, item.source == .agent {
                if let touch = item.lastTouchedConversationId {
                    return touch == conversationId
                }
                return TodoChatDisplayPolicy.itemAppearsInChat(
                    item,
                    conversationId: conversationId,
                    scopeSnapshot: scopeSnapshot
                )
            }
            return false
        }
    }
}
