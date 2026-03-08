import CoderEngine
import Foundation

// MARK: - Action Output & Event Processing

extension CodeReviewPanelStore {

    func beginPanelActionOutput(
        title: String,
        detail: String? = nil,
        selectChatTab: Bool = true
    ) -> UUID {
        ensureActiveChatThread()
        if selectChatTab {
            selectTab(.chat)
        }
        appendChatMessage(
            ReviewPanelChatMessageFactory.commandInvocation(
                title: title,
                detail: detail
            )
        )
        let assistantId = UUID()
        appendChatMessage(ReviewPanelMessage(
            id: assistantId,
            role: .assistant,
            kind: .reviewRun,
            content: "",
            isStreaming: true
        ))
        return assistantId
    }

    func streamPanelActionOutput(id: UUID, event: StreamEvent) {
        switch event {
        case .started:
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Review stream started"
            )
        case .completed:
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Review stream completed"
            )
        case .textDelta(let delta):
            let current = chatMessages.first(where: { $0.id == id })?.content ?? ""
            updateChatMessage(id: id, content: current + delta)
        case .textReplace(let replacement):
            updateChatMessage(id: id, content: replacement)
        case .raw(let type, let payload):
            handleRawReviewRunEvent(id: id, type: type, payload: payload)
        case .error(let message):
            appendReviewRunSectionLine(
                id: id,
                sectionTitle: "Activity",
                line: "Error: \(message)"
            )
        }
    }

    func finishPanelActionOutput(id: UUID, fallbackContent: String? = nil) {
        if let fallbackContent,
           let message = chatMessages.first(where: { $0.id == id }),
           message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateChatMessage(id: id, content: fallbackContent)
        }
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        persistChatState()
    }

    func failPanelActionOutput(id: UUID, error: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].content = "Error: \(error)"
        chatMessages[index].isStreaming = false
        ReviewPanelChatMessageFactory.finalizeReviewRunMessage(&chatMessages[index])
        persistChatState()
    }

    // MARK: - Raw Event Handling

    func handleRawReviewRunEvent(
        id: UUID,
        type: String,
        payload: [String: String]
    ) {
        ingestRawReviewActivity(type: type, payload: payload)
        syncTodoIfNeeded(type: type, payload: payload)

        guard let formatted = formattedReviewRunEvent(type: type, payload: payload) else {
            return
        }
        appendReviewRunSectionLine(
            id: id,
            sectionTitle: formatted.sectionTitle,
            line: formatted.line
        )
    }

    func ingestRawReviewActivity(
        type: String,
        payload: [String: String]
    ) {
        let enrichedPayload = enrichedReviewRawPayload(type: type, payload: payload)
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: effectivePanelProviderId ?? "review-panel",
            type: type,
            payload: enrichedPayload
        )
        taskActivityStore.addEnvelope(envelope)
        for event in envelope.events {
            if case .taskActivity(let activity) = event {
                taskActivityStore.addActivity(
                    scopedTaskActivity(activity)
                )
            }
        }
    }

    func enrichedReviewRawPayload(
        type: String,
        payload: [String: String]
    ) -> [String: String] {
        var enriched = payload
        switch type {
        case "review-worker-plan":
            if let workerId = firstNonEmpty([payload["worker_id"], payload["id"]]) {
                enriched["swarm_id"] = workerId
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(workerId)"
                enriched["agent_name"] = payload["agent_name"] ?? workerId
                enriched["title"] = payload["title"] ?? payload["description"] ?? workerId
                if enriched["detail"] == nil {
                    enriched["detail"] = "planned"
                }
            }
        case "review-audit-tool":
            if let tool = firstNonEmpty([payload["tool"]]) {
                let swarmId = "audit-\(tool)"
                enriched["swarm_id"] = swarmId
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"] ?? tool
                enriched["title"] = payload["title"] ?? tool
            }
        case "agent":
            if let swarmId = firstNonEmpty([payload["swarm_id"], payload["swarmId"]]) {
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"] ?? payload["title"] ?? swarmId
            }
        default:
            break
        }
        return enriched
    }

    func syncTodoIfNeeded(
        type: String,
        payload: [String: String]
    ) {
        guard type == "todo_write" || payload.keys.contains(where: { $0.hasPrefix("todo_") }) else {
            return
        }
        guard let todoStore,
              let parsedTodo = EventNormalizer.parseTodoWrite(payload: payload)
        else {
            return
        }

        todoStore.upsertFromAgent(
            id: parsedTodo.id,
            title: parsedTodo.title,
            status: parsedTodo.status,
            priority: parsedTodo.priority,
            notes: parsedTodo.notes,
            activeForm: parsedTodo.activeForm,
            linkedFiles: parsedTodo.files,
            conversationId: conversationId
        )
    }

    func scopedTaskActivity(_ activity: TaskActivity) -> TaskActivity {
        guard let conversationId else { return activity }
        var payload = activity.payload
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }

    func formattedReviewRunEvent(
        type: String,
        payload: [String: String]
    ) -> (sectionTitle: String, line: String)? {
        switch type {
        case "reasoning":
            if let detail = firstNonEmpty([
                payload["detail"], payload["text"], payload["delta"], payload["content"], payload["summary"],
            ]) {
                return ("Thinking", detail)
            }
        case "review-worker-plan":
            let description = firstNonEmpty([payload["description"], payload["title"]]) ?? "Planned worker"
            let severity = payload["severity"].map { "[\($0)] " } ?? ""
            let fileCount = payload["fileCount"].map { " (\($0) files)" } ?? ""
            return ("Planned Work", "- [ ] \(severity)\(description)\(fileCount)")
        case "review-fix-round":
            let round = payload["round"] ?? "?"
            let maxRounds = payload["maxRounds"] ?? "?"
            return ("Progress", "Round \(round)/\(maxRounds)")
        case "review-audit-tool":
            let tool = payload["tool"] ?? "audit"
            let detail = payload["detail"] ?? "completed"
            return ("Audit", "\(tool): \(detail)")
        case "agent":
            let title = payload["title"] ?? payload["agent_name"] ?? "agent"
            let detail = payload["detail"] ?? payload["status"] ?? "updated"
            return ("Activity", "\(title) — \(detail)")
        case "tool_execution_error", "tool_validation_error":
            let detail = payload["detail"] ?? payload["title"] ?? "Tool error"
            return ("Activity", "Error: \(detail)")
        default:
            if let detail = firstNonEmpty([
                payload["detail"],
                payload["title"],
                payload["summary"],
                payload["status"],
                payload["tool"],
                payload["type"],
            ]) {
                return ("Activity", "\(type): \(detail)")
            }
            return ("Activity", type)
        }
        return nil
    }
}
