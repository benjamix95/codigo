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
                let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let existingBeforeUpsert = todoStore.todos.first(where: { $0.id == todoId })?.planConversationId
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
                let effectiveAfterUpsert = conversationId
                    ?? todoStore.planConversationIdForRuntimeTodoAfterUpsert(
                        preferredId: todoId,
                        normalizedTitle: normalizedTitle,
                        eventConversationId: conversationId
                    )
                    ?? existingBeforeUpsert
                if status == .done {
                    _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: effectiveAfterUpsert)
                }
                if patch.shouldEmitTraceUpdate,
                   let traceConversationId = conversationId ?? effectiveAfterUpsert
                {
                    onTraceUpdate?(patch, traceConversationId, status, patch.linkedFiles)
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
                let patchRemovalConversationId = patch.conversationId.flatMap(UUID.init(uuidString:))
                let existingRemovalConversationId = todoStore.todos.first(where: { $0.id == todoId })?
                    .planConversationId
                let effectiveRemovalConversationId = patchRemovalConversationId ?? existingRemovalConversationId
                // #region agent log
                ComposerTodoDebugNDJSONLog.append(
                    hypothesisId: "H6",
                    location: "MainChatTodoPatchAdapter.swift:removeTodo",
                    message: "rust_remove_todo_then_maybe_advance",
                    runId: "post-fix",
                    data: [
                        "todoId8": String(todoId.uuidString.prefix(8)),
                        "conv8": effectiveRemovalConversationId.map { String($0.uuidString.prefix(8)) } ?? "nil",
                    ]
                )
                // #endregion
                todoStore.remove(id: todoId)
                _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: effectiveRemovalConversationId)
            case .clearMessageRuntimeState:
                continue
            }
        }
    }
}
