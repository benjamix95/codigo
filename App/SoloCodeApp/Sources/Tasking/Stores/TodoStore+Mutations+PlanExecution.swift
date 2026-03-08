import Foundation

extension TodoStore {
    enum PlanBuildPreparationStrategy {
        case resumeIfPossible
        case restartFromBeginning
    }

    /// Prepares canonical plan todos for build start.
    /// - `resumeIfPossible`: keeps completed todos and resumes from first incomplete step.
    /// - `restartFromBeginning`: sets first todo to in_progress and resets all others to pending.
    @discardableResult
    func prepareCanonicalPlanTodosForBuild(
        conversationId: UUID?,
        strategy: PlanBuildPreparationStrategy = .resumeIfPossible
    ) -> [TodoItem] {
        let isInScope = canonicalScopeFilter(for: conversationId)
        let orderedTodoIds = sortedCanonicalFirstTodos(todos.filter { isInScope($0) }).map(\.id)
        guard !orderedTodoIds.isEmpty else { return [] }

        let doneCount = orderedTodoIds.compactMap { id in
            todos.first(where: { $0.id == id })?.status
        }.filter { $0 == .done }.count
        let hasInProgress = orderedTodoIds.contains { id in
            todos.first(where: { $0.id == id })?.status == .inProgress
        }
        let shouldResume = strategy == .resumeIfPossible
            && (hasInProgress || (doneCount > 0 && doneCount < orderedTodoIds.count))

        let resumeAnchorId: UUID? = {
            guard shouldResume else { return nil }
            if let active = orderedTodoIds.first(where: { id in
                todos.first(where: { $0.id == id })?.status == .inProgress
            }) {
                return active
            }
            return orderedTodoIds.first(where: { id in
                guard let status = todos.first(where: { $0.id == id })?.status else { return false }
                return status != .done
            })
        }()

        var didMutate = false
        for (order, id) in orderedTodoIds.enumerated() {
            guard let idx = todos.firstIndex(where: { $0.id == id }) else { continue }
            let currentStatus = todos[idx].status
            let targetStatus: TodoStatus = {
                if shouldResume, let resumeAnchorId {
                    if id == resumeAnchorId { return .inProgress }
                    if currentStatus == .done { return .done }
                    return .pending
                }
                return (order == 0) ? .inProgress : .pending
            }()
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

            if targetStatus == .inProgress {
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
