import CoderEngine
import Foundation

enum PipelineUIEventAdapter {
    static func events(
        from event: PipelineUIEvent,
        conversationId: UUID,
        assistantMessageId: UUID,
        turnId: String,
        providerId: String
    ) -> [ChatPipelineEvent] {
        switch event {
        case .jobStarted(let payload):
            return [lifecycle(.turnStarted, conversationId, assistantMessageId, turnId, providerId, payload.taskCount > 0 ? "streaming" : "idle")]
        case .jobCompleted(let payload):
            return [lifecycle(.turnCompleted, conversationId, assistantMessageId, turnId, providerId, "completed", "Pipeline completed: \(payload.completedTasks)/\(payload.totalTasks) tasks in \(payload.durationMs)ms")]
        case .jobFailed(let payload):
            return [lifecycle(.turnFailed, conversationId, assistantMessageId, turnId, providerId, "failed", payload.reason)]
        case .taskStarted(let payload):
            return [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: 0,
                    source: providerId,
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "task-started-\(payload.taskId)",
                        "title": payload.title.isEmpty ? payload.agentName : payload.title,
                        "detail": "\(payload.role.displayName): in progress",
                        "status": "running",
                        "provider_id": providerId,
                    ]
                ),
            ]
        case .taskCompleted(let payload):
            return [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: 0,
                    source: providerId,
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "task-completed-\(payload.taskId)",
                        "title": payload.title.isEmpty ? payload.agentName : payload.title,
                        "detail": "\(payload.role.displayName): completed in \(payload.durationMs)ms",
                        "status": "completed",
                        "provider_id": providerId,
                    ]
                ),
            ]
        case .taskFailed(let payload):
            let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: 0,
                    source: providerId,
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "task-failed-\(payload.taskId)",
                        "title": title.isEmpty ? "Task failed" : title,
                        "detail": payload.error,
                        "status": "failed",
                        "provider_id": providerId,
                    ]
                ),
            ]
        case .textDelta(let payload):
            return [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: 0,
                    source: providerId,
                    kind: .textDelta,
                    payload: [
                        "delta": payload.delta,
                        "task_id": payload.taskId,
                        "stream_id": payload.taskId,
                        "provider_id": providerId,
                    ]
                ),
            ]
        case .textReplace(let payload):
            return [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: turnId,
                    sequence: 0,
                    source: providerId,
                    kind: .textReplace,
                    payload: [
                        "replacement": payload.replacement,
                        "task_id": payload.taskId,
                        "stream_id": payload.taskId,
                        "provider_id": providerId,
                    ]
                ),
            ]
        default:
            return []
        }
    }

    private static func lifecycle(
        _ kind: ChatPipelineEventKind,
        _ conversationId: UUID,
        _ assistantMessageId: UUID,
        _ turnId: String,
        _ providerId: String,
        _ status: String,
        _ detail: String? = nil
    ) -> ChatPipelineEvent {
        var payload = ["status": status, "provider_id": providerId]
        if let detail, !detail.isEmpty {
            payload["detail"] = detail
        }
        return ChatPipelineEvent(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            sequence: 0,
            source: providerId,
            kind: kind,
            payload: payload
        )
    }
}
