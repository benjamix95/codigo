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
                // #region agent log
                ComposerTodoDebugNDJSONLog.append(
                    hypothesisId: "H3",
                    location: "ChatPanelView+PartF_TodoEvents.swift:handleTodoWriteEvent",
                    message: "plan_todo_upserted",
                    data: [
                        "titleLen": "\(todo.title.count)",
                        "status": todo.status?.rawValue ?? "nil",
                        "willAdvance": "\(todo.status == .done)",
                        "planId8": String(sourcePlanId.uuidString.prefix(8)),
                    ]
                )
                // #endregion
                if todo.status == .done {
                    _ = todoStore.advanceNextExecutionTodoIfNeeded(conversationId: sourcePlanId)
                }
                let canonicalTodos = todoStore.canonicalTodos(for: sourcePlanId)
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: sourcePlanId)
            }
        } else {
            let normalizedTitle = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingBeforeUpsert = todo.id.flatMap { id in
                todoStore.todos.first(where: { $0.id == id })?.effectiveRuntimeQueueConversationId
            }
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
            let missingFollowUps = TodoExecutionFollowUpPolicy.missingFinalFollowUpTitles(
                in: todoStore.todos,
                conversationId: conversationId
            )
            for title in missingFollowUps {
                let isReview = TodoExecutionFollowUpPolicy.isReviewTitle(title)
                todoStore.upsertFromAgent(
                    id: nil,
                    title: title,
                    status: .pending,
                    priority: isReview ? .high : .medium,
                    notes: isReview
                        ? "Review all changed files and run tests"
                        : "Document the completed work, bugs found, verification, and changelog",
                    activeForm: isReview
                        ? "Reviewing code and running tests"
                        : "Writing documentation for the completed work",
                    linkedFiles: [],
                    conversationId: conversationId
                )
            }
            if todo.status == .done {
                let effectiveAfterUpsert = conversationId
                    ?? todoStore.planConversationIdForRuntimeTodoAfterUpsert(
                        preferredId: todo.id,
                        normalizedTitle: normalizedTitle,
                        eventConversationId: conversationId
                    )
                    ?? existingBeforeUpsert
                _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: effectiveAfterUpsert)
            }
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
