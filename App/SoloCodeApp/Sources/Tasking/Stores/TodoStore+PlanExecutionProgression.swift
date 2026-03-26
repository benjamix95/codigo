import Foundation

extension TodoStore {
    @discardableResult
    func upsertCanonicalFromExecutionFallback(
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        activeForm: String?,
        linkedFiles: [String],
        conversationId: UUID?
    ) -> Bool {
        let scoped = canonicalTodos(for: conversationId)
        guard !scoped.isEmpty else { return false }

        let targetId = fallbackCanonicalTodoId(
            status: status,
            scopedCanonicalTodos: scoped
        )
        guard let targetId,
              let idx = todos.firstIndex(where: { $0.id == targetId }) else {
            return false
        }

        let previousStatus = todos[idx].status
        if let status { todos[idx].status = status }
        if let priority { todos[idx].priority = priority }
        if let notes, !notes.isEmpty { todos[idx].notes = notes }
        if !linkedFiles.isEmpty {
            todos[idx].linkedFiles = Array(Set(todos[idx].linkedFiles + linkedFiles)).sorted()
        }
        if let activeForm, !activeForm.isEmpty {
            todos[idx].activeForm = activeForm
        } else if todos[idx].status != .inProgress {
            todos[idx].activeForm = ""
        }
        todos[idx].updatedAt = .now

        saveTodos()
        if todos[idx].status != previousStatus {
            onCanonicalTodoStatusChange?(
                todos[idx].title,
                todos[idx].status,
                todos[idx].planConversationId
            )
        }
        return true
    }

    @discardableResult
    func advanceNextCanonicalTodoIfNeeded(conversationId: UUID?) -> Bool {
        let scoped = canonicalTodos(for: conversationId)
        // #region agent log
        let scopedSummary = scoped
            .map { "\($0.id.uuidString.prefix(8)):\($0.status.rawValue)" }
            .joined(separator: ",")
        // #endregion
        guard !scoped.isEmpty else {
            // #region agent log
            ComposerTodoDebugNDJSONLog.append(
                hypothesisId: "H3",
                location: "TodoStore+PlanExecutionProgression.swift:advanceNext",
                message: "advance_skip_empty_scoped",
                data: ["scoped": scopedSummary]
            )
            // #endregion
            return false
        }
        guard !scoped.contains(where: { $0.status == .inProgress }) else {
            // #region agent log
            ComposerTodoDebugNDJSONLog.append(
                hypothesisId: "H3",
                location: "TodoStore+PlanExecutionProgression.swift:advanceNext",
                message: "advance_skip_already_in_progress",
                data: ["scoped": String(scopedSummary.prefix(500))]
            )
            // #endregion
            return false
        }
        guard let nextPending = scoped.first(where: { $0.status == .pending }),
              let idx = todos.firstIndex(where: { $0.id == nextPending.id }) else {
            // #region agent log
            ComposerTodoDebugNDJSONLog.append(
                hypothesisId: "H3",
                location: "TodoStore+PlanExecutionProgression.swift:advanceNext",
                message: "advance_skip_no_pending",
                data: ["scoped": String(scopedSummary.prefix(500))]
            )
            // #endregion
            return false
        }

        let previousStatus = todos[idx].status
        guard previousStatus != .inProgress else { return false }
        todos[idx].status = .inProgress
        if todos[idx].activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            todos[idx].activeForm = todos[idx].title
        }
        todos[idx].updatedAt = .now

        saveTodos()
        if todos[idx].status != previousStatus {
            onCanonicalTodoStatusChange?(
                todos[idx].title,
                todos[idx].status,
                todos[idx].planConversationId
            )
        }
        // #region agent log
        ComposerTodoDebugNDJSONLog.append(
            hypothesisId: "H3",
            location: "TodoStore+PlanExecutionProgression.swift:advanceNext",
            message: "advance_promoted_pending_to_in_progress",
            data: [
                "nextId8": String(nextPending.id.uuidString.prefix(8)),
                "scoped": String(scopedSummary.prefix(500)),
            ]
        )
        // #endregion
        return true
    }
}

private extension TodoStore {
    func fallbackCanonicalTodoId(
        status: TodoStatus?,
        scopedCanonicalTodos: [TodoItem]
    ) -> UUID? {
        switch status {
        case .done, .blocked:
            return scopedCanonicalTodos.first(where: { $0.status == .inProgress })?.id
                ?? scopedCanonicalTodos.first(where: { $0.status != .done })?.id
        case .inProgress:
            return scopedCanonicalTodos.first(where: { $0.status == .inProgress })?.id
                ?? scopedCanonicalTodos.first(where: { $0.status == .pending })?.id
        case .pending, .none:
            return scopedCanonicalTodos.first(where: { $0.status == .inProgress })?.id
                ?? scopedCanonicalTodos.first(where: { $0.status == .pending })?.id
        }
    }
}
