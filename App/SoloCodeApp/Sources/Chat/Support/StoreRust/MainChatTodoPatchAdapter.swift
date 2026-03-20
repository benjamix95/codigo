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
                if todoStore.todos.contains(where: { $0.id == todoId }) {
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
                } else {
                    todoStore.todos.append(
                        TodoItem(
                            id: todoId,
                            title: title,
                            status: status,
                            priority: priority,
                            source: .agent,
                            notes: patch.notes ?? "",
                            linkedFiles: patch.linkedFiles,
                            planConversationId: conversationId,
                            activeForm: patch.activeForm ?? ""
                        )
                    )
                    todoStore.saveTodos()
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
