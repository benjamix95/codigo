import Foundation

extension TodoStore {
    func orderedRuntimeExecutionTodos(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { lhs, rhs in
            let lhsRank = TodoExecutionFollowUpPolicy.runtimeOrderRank(for: lhs)
            let rhsRank = TodoExecutionFollowUpPolicy.runtimeOrderRank(for: rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    @discardableResult
    func advanceNextExecutionTodoIfNeeded(conversationId: UUID?) -> Bool {
        if advanceNextCanonicalTodoIfNeeded(conversationId: conversationId) {
            return true
        }
        return advanceNextRuntimeTodoIfNeeded(conversationId: conversationId)
    }
}
