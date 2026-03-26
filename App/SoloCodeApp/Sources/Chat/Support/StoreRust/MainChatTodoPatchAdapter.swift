import Foundation

enum MainChatTodoPatchAdapter {
    @MainActor
    static func apply(
        _ patches: [MainChatUITodoPatchBridge],
        to todoStore: TodoStore,
        onTraceUpdate: ((MainChatUITodoPatchBridge, UUID, TodoStatus, [String]) -> Void)? = nil
    ) {
        for patch in patches {
            guard let mutation = patch.mutation else { continue }
            switch mutation {
            case .upsertRuntimeTodo:
                guard let todoId = patch.todoId.flatMap(UUID.init(uuidString:)),
                      let title = patch.title,
                      let status = patch.status.flatMap(TodoStatus.init(rawValue:)),
                      let priority = patch.priority.flatMap(TodoPriority.init(rawValue:))
                else {
                    continue
                }
                let conversationId = patch.conversationId.flatMap(UUID.init(uuidString:))
                // Always use upsertFromAgent — it has 3-level deduplication:
                // 1. Match by exact ID
                // 2. Match by canonical key (fuzzy)
                // 3. Match by case-insensitive title within scope
                // Direct append bypassed all dedup and caused 100+ duplicate tasks.
                todoStore.upsertFromAgent(
                    id: todoId,
                    title: title,
                    status: status,
                    priority: priority,
                    notes: patch.notes,
                    activeForm: patch.activeForm,
                    isOperationalPlaceholder: patch.isOperationalPlaceholder ?? false,
                    linkedFiles: patch.linkedFiles,
                    conversationId: conversationId
                )
                if status == .done, let conversationId {
                    _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: conversationId)
                }
                if patch.shouldEmitTraceUpdate,
                   let conversationId
                {
                    onTraceUpdate?(patch, conversationId, status, patch.linkedFiles)
                }
            case .setStatus:
                guard let todoId = patch.todoId.flatMap(UUID.init(uuidString:)),
                      let status = patch.status.flatMap(TodoStatus.init(rawValue:))
                else {
                    continue
                }
                let existingConversationId = todoStore.todos.first(where: { $0.id == todoId })?.planConversationId
                let patchConversationId = patch.conversationId.flatMap(UUID.init(uuidString:))
                let effectiveConversationId = patchConversationId ?? existingConversationId
                todoStore.setStatus(id: todoId, status: status)
                if status == .done {
                    _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: effectiveConversationId)
                }
                if patch.shouldEmitTraceUpdate,
                   let traceConversationId = patchConversationId ?? existingConversationId
                {
                    onTraceUpdate?(patch, traceConversationId, status, patch.linkedFiles)
                }
            case .removeTodo:
                guard let todoId = patch.todoId.flatMap(UUID.init(uuidString:)) else { continue }
                let removalConversationId = patch.conversationId.flatMap(UUID.init(uuidString:))
                // #region agent log
                ComposerTodoDebugNDJSONLog.append(
                    hypothesisId: "H6",
                    location: "MainChatTodoPatchAdapter.swift:removeTodo",
                    message: "rust_remove_todo_then_maybe_advance",
                    runId: "post-fix",
                    data: [
                        "todoId8": String(todoId.uuidString.prefix(8)),
                        "conv8": removalConversationId.map { String($0.uuidString.prefix(8)) } ?? "nil",
                    ]
                )
                // #endregion
                todoStore.remove(id: todoId)
                if let removalConversationId {
                    _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: removalConversationId)
                }
            case .clearMessageRuntimeState:
                continue
            }
        }
    }
}
