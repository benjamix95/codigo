import Foundation

extension TodoStore {
    /// Resets canonical plan todos for a fresh execution pass:
    /// first todo -> in_progress, remaining todos -> pending.
    @discardableResult
    func prepareCanonicalPlanTodosForBuild(conversationId: UUID?) -> [TodoItem] {
        let isInScope = canonicalScopeFilter(for: conversationId)
        let orderedTodoIds = sortedCanonicalFirstTodos(todos.filter { isInScope($0) }).map(\.id)
        guard !orderedTodoIds.isEmpty else { return [] }

        var didMutate = false
        for (order, id) in orderedTodoIds.enumerated() {
            guard let idx = todos.firstIndex(where: { $0.id == id }) else { continue }
            let targetStatus: TodoStatus = (order == 0) ? .inProgress : .pending
            let previousStatus = todos[idx].status
            var itemMutated = false

            if previousStatus != targetStatus {
                todos[idx].status = targetStatus
                onCanonicalTodoStatusChange?(
                    todos[idx].title,
                    targetStatus,
                    todos[idx].planConversationId
                )
                itemMutated = true
            }

            if todos[idx].planOrder != order {
                todos[idx].planOrder = order
                itemMutated = true
            }

            if order == 0 {
                let normalizedActive = todos[idx].activeForm.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedActive.isEmpty {
                    todos[idx].activeForm = todos[idx].title
                    itemMutated = true
                }
            } else if !todos[idx].activeForm.isEmpty {
                todos[idx].activeForm = ""
                itemMutated = true
            }

            if itemMutated {
                todos[idx].updatedAt = .now
                didMutate = true
            }
        }

        if didMutate {
            saveTodos()
        }
        return canonicalTodos(for: conversationId)
    }
}
