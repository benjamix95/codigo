import Foundation

extension TodoStore {
    func remove(id: UUID) {
        if let todo = todos.first(where: { $0.id == id }), todo.isPlanCanonical {
            // Il wiring principale (ChatPanelView) risincronizza dal solo elenco canonico; lo
            // stato .blocked è storico ma non determina il payload di sync.
            onCanonicalTodoStatusChange?(todo.title, .blocked, todo.planConversationId)
        }
        todos.removeAll { $0.id == id }
        saveTodos()
    }

    func setStatus(id: UUID, status: TodoStatus) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let oldStatus = todos[idx].status
        todos[idx].status = status
        if oldStatus == .inProgress, status != .inProgress {
            todos[idx].activeForm = ""
        }
        todos[idx].updatedAt = .now
        saveTodos()
        if todos[idx].isPlanCanonical, status != oldStatus {
            onCanonicalTodoStatusChange?(todos[idx].title, status, todos[idx].planConversationId)
        }
    }

    func setPriority(id: UUID, priority: TodoPriority) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].priority = priority
        todos[idx].updatedAt = .now
        saveTodos()
    }

    func clear() {
        todos.removeAll()
        saveTodos()
    }

    /// Rimuove solo i todo agent **canonici del piano** in scope (preserva i todo runtime per turni successivi).
    func clearCanonicalAgentTodos(
        conversationId: UUID?,
        preserveCompleted: Bool = true
    ) {
        let isCanonicalInScope = canonicalScopeFilter(for: conversationId)
        todos.removeAll { item in
            guard item.source == .agent,
                  item.isPlanCanonical,
                  isCanonicalInScope(item) else {
                return false
            }
            if preserveCompleted, item.status == .done {
                return false
            }
            return true
        }
        saveTodos()
    }

    func clearAgentTodos(
        conversationId: UUID? = nil,
        includePlanCanonical: Bool = false,
        preserveCompleted: Bool = true
    ) {
        let isRuntimeInScope = runtimeScopeFilter(for: conversationId)
        let isCanonicalInScope = canonicalScopeFilter(for: conversationId)
        if includePlanCanonical {
            todos.removeAll { item in
                guard item.source == .agent else { return false }
                if preserveCompleted, item.status == .done { return false }
                if item.isPlanCanonical {
                    return isCanonicalInScope(item)
                }
                return isRuntimeInScope(item)
            }
        } else {
            todos.removeAll { item in
                item.source == .agent
                    && !item.isPlanCanonical
                    && (!preserveCompleted || item.status != .done)
                    && isRuntimeInScope(item)
            }
        }
        saveTodos()
    }

    /// Rimuove i todo il cui `planConversationId` coincide con la conversazione, più i runtime agent
    /// unscoped il cui `lastTouchedConversationId` è questa conversazione.
    /// - Parameter alsoRemoveLegacyUnscopedAgentRuntime: se `true`, rimuove anche i todo **agent** runtime
    ///   senza scope (`planConversationId == nil`). Da usare con cautela in multi-chat: la sidebar lo attiva
    ///   solo quando si elimina l’ultima conversazione (`conversations.count <= 1`), così la coda globale non
    ///   interferisce con un workspace appena ripulito; con più thread resta `false`.
    func clearTodos(
        forConversationId conversationId: UUID,
        alsoRemoveLegacyUnscopedAgentRuntime: Bool = false
    ) {
        todos.removeAll { $0.planConversationId == conversationId }
        todos.removeAll { item in
            item.source == .agent
                && !item.isPlanCanonical
                && !item.isOperationalPlaceholder
                && item.planConversationId == nil
                && item.lastTouchedConversationId == conversationId
        }
        if alsoRemoveLegacyUnscopedAgentRuntime {
            todos.removeAll { item in
                item.source == .agent
                    && !item.isPlanCanonical
                    && !item.isOperationalPlaceholder
                    && item.planConversationId == nil
            }
        }
        saveTodos()
    }
}
