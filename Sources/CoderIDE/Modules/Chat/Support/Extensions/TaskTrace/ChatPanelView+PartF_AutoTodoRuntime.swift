import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func startAutoTodoIfNeeded(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        guard shouldTrackAutoTodo(for: activity, conversationId: conversationId) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }

        let messageId = turn.assistantMessageId
        guard autoTodoIdByMessage[messageId] == nil else { return }
        guard !didReceiveExplicitTodoByMessage.contains(messageId) else { return }

        let todoId = UUID()
        let title = autoTodoTitle(for: activity)
        let linkedFiles = autoTodoLinkedFiles(from: activity.payload)
        let notes = autoTodoRuntimeNotes(operationCount: 0)
        let activeForm = preferredAutoTodoActiveForm(
            currentActiveForm: "",
            immediateLabel: Self.immediateSubtitleLabel(for: activity),
            title: title
        )

        todoStore.upsertFromAgent(
            id: todoId,
            title: title,
            status: .inProgress,
            priority: .medium,
            notes: notes,
            activeForm: activeForm,
            linkedFiles: linkedFiles,
            conversationId: turn.conversationId
        )
        autoTodoIdByMessage[messageId] = todoId
        autoTodoCompletedOperationsByMessage[messageId] = 0

        emitAutoTodoTraceUpdate(
            todoId: todoId,
            title: title,
            status: .inProgress,
            notes: notes,
            linkedFiles: linkedFiles,
            providerId: providerId,
            conversationId: turn.conversationId,
            timestamp: activity.timestamp
        )
    }

    @MainActor
    internal func refreshAutoTodoIfNeeded(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        guard shouldTrackAutoTodo(for: activity, conversationId: conversationId) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }

        let messageId = turn.assistantMessageId
        guard !didReceiveExplicitTodoByMessage.contains(messageId) else { return }
        guard let autoTodoId = autoTodoIdByMessage[messageId] else { return }

        let operationCount = (autoTodoCompletedOperationsByMessage[messageId] ?? 0) + 1
        autoTodoCompletedOperationsByMessage[messageId] = operationCount

        let existingTodo = todoStore.todos.first(where: { $0.id == autoTodoId })
        let title = preferredAutoTodoTitle(
            currentTitle: existingTodo?.title,
            candidateTitle: autoTodoTitle(for: activity)
        )
        let linkedFiles = mergedAutoTodoLinkedFiles(
            existing: existingTodo?.linkedFiles ?? [],
            incoming: autoTodoLinkedFiles(from: activity.payload)
        )
        let notes = autoTodoRuntimeNotes(operationCount: operationCount)
        let activeForm = preferredAutoTodoActiveForm(
            currentActiveForm: existingTodo?.activeForm ?? "",
            immediateLabel: Self.immediateSubtitleLabel(for: activity),
            title: title
        )

        todoStore.upsertFromAgent(
            id: autoTodoId,
            title: title,
            status: .inProgress,
            priority: existingTodo?.priority ?? .medium,
            notes: notes,
            activeForm: activeForm,
            linkedFiles: linkedFiles,
            conversationId: turn.conversationId
        )
    }

    @MainActor
    internal func shouldTrackAutoTodo(
        for activity: TaskActivity,
        conversationId: UUID?
    ) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return false
        }
        return isOperationalTraceActivity(activity)
    }
}
