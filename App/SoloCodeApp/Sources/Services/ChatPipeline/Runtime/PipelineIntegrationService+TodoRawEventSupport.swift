import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func handleRawTodoWrite(_ p: RawEventPayload, for conversationId: UUID) {
        guard let todoStore, let runtime = runtime(for: conversationId) else { return }
        let normalizedResult = EventNormalizer.normalizeTodoWrite(
            payload: p.payload,
            timestamp: .now
        )
        if normalizedResult == nil {
            NSLog(
                "[PipelineIntegration] normalizeTodoWrite returned nil for payload keys: %@",
                p.payload.keys.joined(separator: ", ")
            )
        }
        let normalizedEvents = normalizedResult ?? []
        let parsedTodos = normalizedEvents.compactMap { event -> TodoWritePayload? in
            if case .todoWrite(let todo) = event {
                return todo
            }
            return nil
        }
        guard !parsedTodos.isEmpty else { return }
        let shouldUseTaskScopedFallbackId = parsedTodos.count == 1

        var canonicalPlanIdsToSync = Set<UUID>()
        todoStore.performBatchUpdates {
            for todo in parsedTodos {
                let todoId = resolvedRawTodoID(
                    from: p,
                    parsedTodo: todo,
                    allowTaskScopedFallback: shouldUseTaskScopedFallbackId
                )
                if let planId = runtime.planConversationId {
                    var updated = todoStore.upsertCanonicalOnlyFromAgent(
                        id: todoId,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        activeForm: todo.activeForm,
                        linkedFiles: todo.files,
                        conversationId: planId
                    )
                    if !updated {
                        updated = todoStore.upsertCanonicalFromExecutionFallback(
                            status: todo.status,
                            priority: todo.priority,
                            notes: todo.notes,
                            activeForm: todo.activeForm,
                            linkedFiles: todo.files,
                            conversationId: planId
                        )
                    }
                    if !updated {
                        NSLog("[PipelineIntegration] todo upsert failed for title: %@", todo.title)
                        continue
                    }
                    canonicalPlanIdsToSync.insert(planId)
                    if todo.status == .done {
                        _ = todoStore.advanceNextExecutionTodoIfNeeded(conversationId: planId)
                    }
                } else {
                    let normalizedTitle = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let existingBeforeUpsert = todoId.flatMap { id in
                        todoStore.todos.first(where: { $0.id == id })?.effectiveRuntimeQueueConversationId
                    }
                    todoStore.upsertFromAgent(
                        id: todoId,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        activeForm: todo.activeForm,
                        linkedFiles: todo.files,
                        conversationId: conversationId
                    )
                    if todo.status == .done {
                        let effectiveAfterUpsert =
                            todoStore.planConversationIdForRuntimeTodoAfterUpsert(
                                preferredId: todoId,
                                normalizedTitle: normalizedTitle,
                                eventConversationId: conversationId
                            ) ?? existingBeforeUpsert ?? conversationId
                        _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: effectiveAfterUpsert)
                    }
                }
            }
        }

        for planId in canonicalPlanIdsToSync {
            let canonicalTodos = todoStore.canonicalTodos(for: planId)
            guard !canonicalTodos.isEmpty else { continue }
            chatStore?.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planId)
        }
    }

    func resolvedRawTodoID(
        from payload: RawEventPayload,
        parsedTodo: TodoWritePayload?,
        allowTaskScopedFallback: Bool
    ) -> UUID? {
        if let direct = parsedTodo?.id {
            return direct
        }
        guard allowTaskScopedFallback else {
            return nil
        }
        return UUID(uuidString: payload.taskId)
    }

    func handleRawPlanStep(_ p: RawEventPayload, for conversationId: UUID) {
        guard let planId = runtime(for: conversationId)?.planConversationId else { return }
        guard let todoStore else { return }

        let canonicalTodos = todoStore.canonicalTodos(for: planId)
        chatStore?.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planId)
    }
}
