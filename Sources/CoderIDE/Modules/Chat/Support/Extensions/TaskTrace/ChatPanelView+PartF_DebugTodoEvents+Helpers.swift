import Foundation

extension ChatPanelView {
    internal func emitAutoTodoTraceUpdate(
        todoId: UUID,
        title: String,
        status: TodoStatus,
        notes: String,
        linkedFiles: [String],
        providerId: String,
        conversationId: UUID?,
        timestamp: Date
    ) {
        var payload: [String: String] = [
            "id": todoId.uuidString,
            "title": title,
            "task": title,
            "status": status.rawValue,
            "priority": TodoPriority.medium.rawValue,
            "notes": notes,
        ]
        if !linkedFiles.isEmpty {
            payload["files"] = linkedFiles.joined(separator: ",")
        }

        let activity = TaskActivity(
            type: "todo_write",
            title: "Todo updated",
            detail: title,
            payload: payload,
            timestamp: timestamp,
            phase: .planning,
            isRunning: false
        )
        enqueueTaskActivity(activity)
        appendToolTraceEvent(
            activity: activity,
            rawKind: .todoUpdate,
            providerId: providerId,
            conversationId: conversationId
        )
    }

    internal func instantGrepWithConversationContext(
        _ grep: InstantGrepResult,
        conversationId: UUID?,
        payload: [String: String]
    ) -> InstantGrepResult {
        let payloadConversationId = payload["conversation_id"]
            .flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let resolvedConversationId = grep.conversationId ?? conversationId ?? payloadConversationId
        if grep.conversationId == resolvedConversationId {
            return grep
        }
        return InstantGrepResult(
            id: grep.id,
            query: grep.query,
            scope: grep.scope,
            matchesCount: grep.matchesCount,
            durationMs: grep.durationMs,
            matches: grep.matches,
            conversationId: resolvedConversationId,
            createdAt: grep.createdAt
        )
    }
}
