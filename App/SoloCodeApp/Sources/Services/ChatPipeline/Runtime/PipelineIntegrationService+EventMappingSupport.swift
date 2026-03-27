import CoderEngine
import Foundation

extension PipelineIntegrationService {

    // MARK: - Inline Marker Processing

    func processInlinePolicyAckMarkersFromPipelineText(
        existingContent: String?,
        incomingContent: String,
        isReplacement: Bool,
        conversationId: UUID
    ) {
        guard let runtime = runtime(for: conversationId),
              let callback = runtime.rawEventHandler else {
            return
        }

        let hashes = inlinePolicyAckHashesForStreamingUpdate(
            existingContent: existingContent,
            incomingContent: incomingContent,
            isReplacement: isReplacement
        )
        guard !hashes.isEmpty else { return }

        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        for hash in hashes {
            callback("policy_ack", ["hash": hash], providerId, conversationId)
        }
    }

    func processInlineTodoWriteMarkersFromPipelineText(
        existingContent: String?,
        incomingContent: String,
        isReplacement: Bool,
        conversationId: UUID
    ) {
        guard let runtime = runtime(for: conversationId),
              let callback = runtime.rawEventHandler else {
            return
        }

        let payloads = inlineTodoWritePayloadsForStreamingUpdate(
            existingContent: existingContent,
            incomingContent: incomingContent,
            isReplacement: isReplacement
        )
        guard !payloads.isEmpty else { return }

        let providerId = runtime.chatTurnState.providerId ?? runtime.providerId
        for payload in payloads {
            callback("todo_write", payload, providerId, conversationId)
        }
    }

    // MARK: - Pipeline Activity Recording

    func recordPipelineSwarmLifecycleActivity(
        agentName: String?,
        title: String,
        detail: String,
        conversationId: UUID,
        isRunning: Bool,
        taskId: String,
        status: String
    ) {
        let resolvedName = (agentName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = resolvedName.isEmpty
            ? title.trimmingCharacters(in: .whitespacesAndNewlines)
            : resolvedName
        var payload = pipelineSwarmPayload(
            taskId: taskId,
            agentName: agentName,
            status: status
        )
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        if !detail.isEmpty {
            payload["detail"] = detail
        }
        taskActivityStore?.addActivity(
            TaskActivity(
                type: "agent",
                title: resolvedTitle.isEmpty ? "Subagent" : resolvedTitle,
                detail: detail,
                payload: payload,
                phase: .executing,
                isRunning: isRunning,
                groupId: payload["group_id"]
            )
        )
    }

    func recordPipelineSubagentTextActivity(
        taskId: String,
        text: String,
        conversationId: UUID
    ) {
        let cleaned = ChatStore.stripCoderideMarkers(text, aggressive: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        var payload = pipelineSwarmPayload(
            taskId: taskId,
            agentName: nil,
            status: "running"
        )
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        payload["text"] = cleaned

        taskActivityStore?.addActivity(
            TaskActivity(
                type: "subagent_text",
                title: "Subagent update",
                detail: String(cleaned.prefix(140)),
                payload: payload,
                phase: .executing,
                isRunning: true,
                groupId: payload["group_id"]
            )
        )
    }

    func recordStructuredPipelineTaskActivity(
        type: String,
        title: String,
        detail: String,
        conversationId: UUID,
        isRunning: Bool,
        taskId: String
    ) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: String] = [
            "conversation_id": conversationId.uuidString.lowercased(),
            "task_id": taskId,
            "group_id": taskId,
            "status": isRunning ? "running" : "completed",
            "owner_kind": "supervisor",
            "supervisor_kind": "orchestrator",
        ]
        taskActivityStore?.addActivity(
            TaskActivity(
                type: type,
                title: normalizedTitle.isEmpty ? "Pipeline task" : normalizedTitle,
                detail: detail,
                payload: payload,
                phase: .executing,
                isRunning: isRunning,
                groupId: taskId
            )
        )
    }

    // MARK: - Todo Persistence Helpers

    func shouldPersistRuntimeTaskAsTodo(
        title: String,
        runtime: PipelineConversationRuntime
    ) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }
        if runtime.planConversationId == nil && max(runtime.totalTasks, 1) <= 1 {
            return false
        }
        return true
    }
}
