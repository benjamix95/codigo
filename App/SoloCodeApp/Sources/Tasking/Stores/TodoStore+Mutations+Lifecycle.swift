import Foundation

extension TodoStore {
    func remove(id: UUID) {
        if let todo = todos.first(where: { $0.id == id }), todo.isPlanCanonical {
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

    func clearAgentTodos(
        conversationId: UUID? = nil,
        includePlanCanonical: Bool = false
    ) {
        let isRuntimeInScope = runtimeScopeFilter(for: conversationId)
        let isCanonicalInScope = canonicalScopeFilter(for: conversationId)
        if includePlanCanonical {
            todos.removeAll { item in
                guard item.source == .agent else { return false }
                if item.isPlanCanonical {
                    return isCanonicalInScope(item)
                }
                return isRuntimeInScope(item)
            }
        } else {
            todos.removeAll { item in
                item.source == .agent
                    && !item.isPlanCanonical
                    && isRuntimeInScope(item)
            }
        }
        saveTodos()
    }

    func clearTodos(forConversationId conversationId: UUID) {
        todos.removeAll { $0.planConversationId == conversationId }
        saveTodos()
    }
}
