import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func handleTodoWriteEvent(
        _ todo: TodoWritePayload,
        providerId: String,
        conversationId: UUID?
    ) {
        if todo.title == EventNormalizer.todoClearMarkerTitle {
            enableTaskPanelIfNeeded()
            let scopedConversationId = resolveTodoClearTargetConversationId(
                eventConversationId: conversationId,
                activeBuildPlanConversationId: activeBuildPlanConversationId,
                activeBuildAgentConversationId: activeBuildAgentConversationId,
                activeTaskConversationId: chatStore.activeTaskConversationId,
                selectedConversationId: self.conversationId
            )
            guard let scopedConversationId else {
                recordExplicitTodoWrite(providerId: providerId, conversationId: conversationId)
                return
            }
            todoStore.clearAgentTodos(
                conversationId: scopedConversationId,
                includePlanCanonical: false
            )
            recordExplicitTodoWrite(providerId: providerId, conversationId: conversationId)
            return
        }

        guard shouldAcceptTodoWrite(todo, conversationId: conversationId) else { return }
        enableTaskPanelIfNeeded()
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            let sourcePlanId = activeBuildPlanConversationId ?? conversationId
            var updated = todoStore.upsertCanonicalOnlyFromAgent(
                id: todo.id,
                title: todo.title,
                status: todo.status,
                priority: todo.priority,
                notes: todo.notes,
                activeForm: todo.activeForm,
                linkedFiles: todo.files,
                conversationId: sourcePlanId
            )
            if !updated {
                updated = todoStore.upsertCanonicalFromExecutionFallback(
                    status: todo.status,
                    priority: todo.priority,
                    notes: todo.notes,
                    activeForm: todo.activeForm,
                    linkedFiles: todo.files,
                    conversationId: sourcePlanId
                )
            }
            if updated, let sourcePlanId {
                if todo.status == .done {
                    _ = todoStore.advanceNextCanonicalTodoIfNeeded(conversationId: sourcePlanId)
                }
                let canonicalTodos = todoStore.canonicalTodos(for: sourcePlanId)
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: sourcePlanId)
            }
        } else {
            todoStore.upsertFromAgent(
                id: todo.id,
                title: todo.title,
                status: todo.status,
                priority: todo.priority,
                notes: todo.notes,
                activeForm: todo.activeForm,
                linkedFiles: todo.files,
                conversationId: conversationId
            )
        }
        recordExplicitTodoWrite(providerId: providerId, conversationId: conversationId)
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "todo_write") {
            streaming.streamContentVersion &+= 1
        }
    }

    @MainActor
    internal func handleTodoReadEvent(conversationId: UUID?) {
        guard shouldAcceptTodoRead(conversationId: conversationId) else { return }
        enableTaskPanelIfNeeded()
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "todo_read") {
            streaming.streamContentVersion &+= 1
        }
    }
}
