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

    func clearAgentTodos(includePlanCanonical: Bool = false) {
        if includePlanCanonical {
            todos.removeAll { $0.source == .agent }
        } else {
            todos.removeAll { $0.source == .agent && !$0.isPlanCanonical }
        }
        saveTodos()
    }
}
