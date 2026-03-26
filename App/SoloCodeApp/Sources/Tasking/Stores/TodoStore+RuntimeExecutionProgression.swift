import Foundation

extension TodoStore {
    /// Avanza il prossimo todo **runtime** (non canonical) quando il modello marca un passo come `done`.
    /// Usato quando non esiste un piano canonico per la conversazione — vedi log `canonIdHead` vuoto con todo in overlay.
    @discardableResult
    func advanceNextRuntimeTodoIfNeeded(conversationId: UUID?) -> Bool {
        let runtimeVisible = userVisibleTodos.filter { item in
            !item.isOperationalPlaceholder && !item.isPlanCanonical
        }

        let pool: [TodoItem]
        if let conversationId {
            // Solo i passi canonici ancora non completati devono bloccare la coda runtime;
            // i canonical `done` restano in store ma non devono congelare l’auto-avanzamento.
            if hasIncompleteCanonicalPlanWork(for: conversationId) { return false }
            pool = displayTodosForChat(for: conversationId).filter {
                !$0.isPlanCanonical && !$0.isOperationalPlaceholder
            }
        } else {
            // Solo coda veramente globale: niente `lastTouched` (altrimenti l’avanzamento va con `conversationId`).
            pool = runtimeVisible.filter {
                $0.planConversationId == nil && $0.lastTouchedConversationId == nil
            }
        }

        guard !pool.isEmpty else { return false }

        let ordered = pool.sorted { lhs, rhs in
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

        let convLog = conversationId.map { String($0.uuidString.prefix(8)) } ?? "unscoped"
        // #region agent log
        ComposerTodoDebugNDJSONLog.append(
            hypothesisId: "H3",
            location: "TodoStore+RuntimeExecutionProgression.swift:advanceNextRuntimeTodoIfNeeded",
            message: "advance_runtime_promoted_pending",
            runId: "post-fix",
            data: [
                "nextId8": String(nextPending.id.uuidString.prefix(8)),
                "conv8": convLog,
            ]
        )
        // #endregion

        return true
    }
}

private extension TodoStore {
    func hasIncompleteCanonicalPlanWork(for conversationId: UUID) -> Bool {
        canonicalTodos(for: conversationId).contains { $0.status != .done }
    }
}
