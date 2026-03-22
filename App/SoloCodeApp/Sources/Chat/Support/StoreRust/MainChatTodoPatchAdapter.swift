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
                    linkedFiles: patch.linkedFiles,
                    conversationId: conversationId
                )
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
                todoStore.setStatus(id: todoId, status: status)
                if patch.shouldEmitTraceUpdate,
                   let conversationId = patch.conversationId.flatMap(UUID.init(uuidString:))
                {
                    onTraceUpdate?(patch, conversationId, status, patch.linkedFiles)
                }
            case .removeTodo:
                guard let todoId = patch.todoId.flatMap(UUID.init(uuidString:)) else { continue }
                todoStore.remove(id: todoId)
            case .clearMessageRuntimeState:
                continue
            }
        }
    }
}
