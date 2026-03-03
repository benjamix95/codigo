import CoderEngine

extension ChatPanelView {
    /// Wire bidirectional sync: when a canonical todo status changes manually,
    /// propagate the change to the corresponding PlanStep in the plan board.
    /// Idempotent — safe to call multiple times (e.g. from onAppear).
    internal func wireTodoPlanBidirectionalSync() {
        // Guard: don't re-register if callback already set (onAppear fires multiple times).
        guard todoStore.onCanonicalTodoStatusChange == nil else { return }
        todoStore.onCanonicalTodoStatusChange = { [weak chatStore] _, _, canonicalConversationId in
            guard let chatStore else { return }
            let planConvId = activeBuildPlanConversationId
                ?? canonicalConversationId
                ?? chatStore.preferredPlanConversationIdForCanonicalSync()
            if let activeId = planConvId {
                let canonicalTodos = todoStore.canonicalTodos(for: activeId)
                guard !canonicalTodos.isEmpty else { return }
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: activeId)
            }
        }
    }
}
