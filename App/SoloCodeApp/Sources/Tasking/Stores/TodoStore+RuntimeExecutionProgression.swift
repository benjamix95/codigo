import Foundation

extension TodoStore {
    /// Avanza il prossimo todo **runtime** (non canonical) quando il modello marca un passo come `done`.
    /// Usato quando non esiste un piano canonico per la conversazione — vedi log `canonIdHead` vuoto con todo in overlay.
    @discardableResult
    func advanceNextRuntimeTodoIfNeeded(conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        if !canonicalTodos(for: conversationId).isEmpty { return false }

        let scoped = userVisibleTodos.filter { item in
            !item.isOperationalPlaceholder
                && !item.isPlanCanonical
                && item.planConversationId == conversationId
        }
        guard !scoped.isEmpty else { return false }

        let ordered = scoped.sorted { lhs, rhs in
            if lhs.priority.rank != rhs.priority.rank { return lhs.priority.rank < rhs.priority.rank }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        guard !ordered.contains(where: { $0.status == .inProgress }) else { return false }
        guard let nextPending = ordered.first(where: { $0.status == .pending }),
              let idx = todos.firstIndex(where: { $0.id == nextPending.id })
        else { return false }

        todos[idx].status = .inProgress
        if todos[idx].activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            todos[idx].activeForm = todos[idx].title
        }
        todos[idx].updatedAt = .now
        saveTodos()

        // #region agent log
        ComposerTodoDebugNDJSONLog.append(
            hypothesisId: "H3",
            location: "TodoStore+RuntimeExecutionProgression.swift:advanceNextRuntimeTodoIfNeeded",
            message: "advance_runtime_promoted_pending",
            runId: "post-fix",
            data: [
                "nextId8": String(nextPending.id.uuidString.prefix(8)),
                "conv8": String(conversationId.uuidString.prefix(8)),
            ]
        )
        // #endregion

        return true
    }
}
