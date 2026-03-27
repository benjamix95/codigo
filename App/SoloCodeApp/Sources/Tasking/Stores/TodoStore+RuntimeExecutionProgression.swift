import Foundation

extension TodoStore {
    /// Avanza il prossimo todo **runtime** (non canonical) quando il modello marca un passo come `done`.
    ///
    /// **Quando passare `conversationId`:**
    /// - Quasi sempre: usa l’ID della chat attiva / dell’evento (`todo_write`, patch Rust, pipeline). La pool è
    ///   allineata a `displayTodosForChat` (stessa semantica delle card).
    ///
    /// **`conversationId == nil` (globale):**
    /// - Solo per una coda **legacy** senza ancoraggio: righe con `planConversationId == nil` **e**
    ///   `lastTouchedConversationId == nil`. I todo “touchati” da un thread non vanno avanzati da qui:
    ///   usa sempre la conversazione effettiva (`effectiveRuntimeQueueConversationId`).
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

        let ordered = orderedRuntimeExecutionTodos(pool)

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

        return true
    }
}

private extension TodoStore {
    func hasIncompleteCanonicalPlanWork(for conversationId: UUID) -> Bool {
        canonicalTodos(for: conversationId).contains { $0.status != .done }
    }
}
