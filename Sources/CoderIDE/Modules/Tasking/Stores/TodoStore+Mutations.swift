import Foundation

extension TodoStore {
    func add(
        title: String,
        source: TodoSource = .manual,
        priority: TodoPriority = .medium,
        notes: String = "",
        activeForm: String = "",
        linkedFiles: [String] = []
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(
            TodoItem(
                title: trimmed,
                priority: priority,
                source: source,
                notes: notes,
                linkedFiles: linkedFiles,
                activeForm: activeForm
            )
        )
        saveTodos()
    }

    func upsertFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        activeForm: String? = nil,
        linkedFiles: [String],
        conversationId: UUID? = nil
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return }
        let isRuntimeInScope = runtimeScopeFilter(for: conversationId)

        func applyActiveForm(at idx: Int) {
            if let activeForm, !activeForm.isEmpty { todos[idx].activeForm = activeForm }
        }

        if let id, let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(
            title: normalizedTitle,
            conversationId: conversationId
        ),
        let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId })
        {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        if let idx = todos.firstIndex(where: {
            isRuntimeInScope($0) && $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            applyActiveForm(at: idx)
            todos[idx].source = .agent
            if let conversationId, !todos[idx].isPlanCanonical {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].updatedAt = .now
            saveTodos()
            return
        }

        let newTodo = TodoItem(
            title: normalizedTitle,
            status: status ?? .pending,
            priority: priority ?? .medium,
            source: .agent,
            notes: notes ?? "",
            linkedFiles: linkedFiles,
            planConversationId: conversationId,
            activeForm: activeForm ?? ""
        )
        todos.append(newTodo)
        saveTodos()
    }

    @discardableResult
    func upsertCanonicalOnlyFromAgent(
        id: UUID?,
        title: String,
        status: TodoStatus?,
        priority: TodoPriority?,
        notes: String?,
        activeForm: String? = nil,
        linkedFiles: [String],
        conversationId: UUID? = nil
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }
        let isInScope = canonicalScopeFilter(for: conversationId)

        func applyUpdate(at idx: Int) {
            todos[idx].title = normalizedTitle
            if let status { todos[idx].status = status }
            if let priority { todos[idx].priority = priority }
            if let notes, !notes.isEmpty { todos[idx].notes = notes }
            if !linkedFiles.isEmpty { todos[idx].linkedFiles = linkedFiles }
            if let activeForm, !activeForm.isEmpty { todos[idx].activeForm = activeForm }
            if let conversationId {
                todos[idx].planConversationId = conversationId
            }
            todos[idx].source = .agent
            todos[idx].updatedAt = .now
            saveTodos()
        }

        if let id, let idx = todos.firstIndex(where: { $0.id == id && isInScope($0) }) {
            applyUpdate(at: idx)
            return true
        }

        if let matchedCanonicalId = bindRuntimeTodoToCanonicalIfMatch(
            title: normalizedTitle,
            conversationId: conversationId
        ),
           let idx = todos.firstIndex(where: { $0.id == matchedCanonicalId && isInScope($0) }) {
            applyUpdate(at: idx)
            return true
        }

        if let idx = todos.firstIndex(where: {
            isInScope($0) && $0.title.caseInsensitiveCompare(normalizedTitle) == .orderedSame
        }) {
            applyUpdate(at: idx)
            return true
        }

        return false
    }

    @discardableResult
    func bindRuntimeTodoToCanonicalIfMatch(title: String, conversationId: UUID? = nil) -> UUID? {
        let key = canonicalKey(for: title)
        guard !key.isEmpty else { return nil }
        let inScope = canonicalScopeFilter(for: conversationId)
        if let exact = todos.first(where: { inScope($0) && canonicalKey(for: $0.title) == key }) {
            return exact.id
        }
        guard key.count >= 12 else { return nil }
        return todos.first(where: {
            guard inScope($0) else { return false }
            let canonical = canonicalKey(for: $0.title)
            return isLikelyCanonicalMatch(titleKey: key, canonicalKey: canonical)
        })?.id
    }

    func upsertCanonicalPlanTodos(_ titles: [String], conversationId: UUID? = nil) {
        var seenKeys = Set<String>()
        let cleaned: [String] = titles.compactMap { (raw: String) -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = canonicalKey(for: trimmed)
            guard seenKeys.insert(key).inserted else { return nil }
            return trimmed
        }
        guard !cleaned.isEmpty else { return }
        let desiredKeys = seenKeys
        let isInScope = canonicalScopeFilter(for: conversationId)

        for idx in todos.indices where isInScope(todos[idx]) {
            let existingKey = canonicalKey(for: todos[idx].title)
            if !desiredKeys.contains(existingKey) {
                let oldStatus = todos[idx].status
                todos[idx].status = .blocked
                todos[idx].notes = "Removed from current plan"
                todos[idx].updatedAt = .now
                if oldStatus != .blocked {
                    onCanonicalTodoStatusChange?(
                        todos[idx].title,
                        .blocked,
                        todos[idx].planConversationId
                    )
                }
            }
        }

        for (index, title) in cleaned.enumerated() {
            let key = canonicalKey(for: title)
            if let idx = todos.firstIndex(where: {
                isInScope($0) && canonicalKey(for: $0.title) == key
            }) {
                todos[idx].title = title
                todos[idx].isPlanCanonical = true
                todos[idx].planOrder = index
                todos[idx].planConversationId = conversationId
                todos[idx].source = .agent
                if todos[idx].status == .blocked {
                    todos[idx].status = .pending
                }
                todos[idx].updatedAt = .now
            } else {
                todos.append(
                    TodoItem(
                        title: title,
                        status: .pending,
                        priority: .medium,
                        source: .agent,
                        notes: "",
                        linkedFiles: [],
                        isPlanCanonical: true,
                        planOrder: index,
                        planConversationId: conversationId
                    )
                )
            }
        }
        saveTodos()
    }
}
