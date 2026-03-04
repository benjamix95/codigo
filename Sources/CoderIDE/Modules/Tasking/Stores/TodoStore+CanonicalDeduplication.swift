import Foundation

extension TodoStore {
    @discardableResult
    func deduplicateCanonicalTodos(
        inScope: ((TodoItem) -> Bool)? = nil
    ) -> Bool {
        var keepIndexByCompositeKey: [String: Int] = [:]
        var removeIndices = Set<Int>()
        var didMutate = false

        for index in todos.indices {
            let item = todos[index]
            guard item.isPlanCanonical else { continue }
            if let inScope, !inScope(item) { continue }

            let key = canonicalKey(for: item.title)
            guard !key.isEmpty else { continue }
            let compositeKey = "\(scopeKey(for: item.planConversationId))::\(key)"

            if let existingIndex = keepIndexByCompositeKey[compositeKey] {
                let merged = mergeCanonicalDuplicate(
                    base: todos[existingIndex],
                    incoming: item
                )
                todos[existingIndex] = merged
                removeIndices.insert(index)
                didMutate = true
                continue
            }

            keepIndexByCompositeKey[compositeKey] = index
        }

        if !removeIndices.isEmpty {
            todos = todos.enumerated().compactMap { offset, item in
                removeIndices.contains(offset) ? nil : item
            }
            didMutate = true
        }

        return didMutate
    }
}

private extension TodoStore {
    func scopeKey(for conversationId: UUID?) -> String {
        conversationId?.uuidString.lowercased() ?? "legacy"
    }

    func mergeCanonicalDuplicate(base: TodoItem, incoming: TodoItem) -> TodoItem {
        var merged = base
        let incomingTitle = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = merged.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if incomingTitle.count > baseTitle.count {
            merged.title = incoming.title
        }

        if canonicalStatusMergeRank(incoming.status) > canonicalStatusMergeRank(merged.status) {
            merged.status = incoming.status
        }

        if incoming.priority.rank < merged.priority.rank {
            merged.priority = incoming.priority
        }

        if merged.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !incoming.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.notes = incoming.notes
        }

        if merged.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !incoming.activeForm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.activeForm = incoming.activeForm
        }

        if let baseOrder = merged.planOrder, let incomingOrder = incoming.planOrder {
            merged.planOrder = min(baseOrder, incomingOrder)
        } else if merged.planOrder == nil {
            merged.planOrder = incoming.planOrder
        }

        if merged.planConversationId == nil {
            merged.planConversationId = incoming.planConversationId
        }

        merged.linkedFiles = Array(Set(merged.linkedFiles + incoming.linkedFiles)).sorted()
        merged.updatedAt = max(merged.updatedAt, incoming.updatedAt)
        return merged
    }

    func canonicalStatusMergeRank(_ status: TodoStatus) -> Int {
        switch status {
        case .done:
            return 3
        case .inProgress:
            return 2
        case .blocked:
            return 1
        case .pending:
            return 0
        }
    }
}
