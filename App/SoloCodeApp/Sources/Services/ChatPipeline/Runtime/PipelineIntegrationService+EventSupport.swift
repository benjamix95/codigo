import CoderEngine
import Foundation

// MARK: - Raw Event Type Constants

private enum RawEventType {
    static let todoWrite = "todo_write"
    static let planStep = "plan_step"
    static let showTaskPanel = "show_task_panel"
    static let assistantUpdate = "assistant_update"
}

extension PipelineIntegrationService {

    // MARK: - Raw Events

    func handleRawEvent(_ p: RawEventPayload, for conversationId: UUID) {
        applyCodexAppServerStreamingMeta(p)
        let rawType = p.rawType
        let normalizedEnvelope = normalizeRawEventEnvelope(p)

        let currentRuntime = runtime(for: conversationId)
        let providerId = currentRuntime?.providerId ?? "pipeline"
        let hasExternalRawHandler = currentRuntime?.rawEventHandler != nil
        if let callback = currentRuntime?.rawEventHandler {
            callback(rawType, p.payload, providerId, conversationId)
        }
        projectAssistantUpdateIntoPrimaryTextIfNeeded(
            rawEvent: p,
            providerId: providerId,
            conversationId: conversationId
        )
        consumeRawPipelineArtifacts(rawType: rawType, payload: p.payload, for: conversationId)

        if rawType == RawEventType.showTaskPanel {
            chatStore?.setTaskStatus(
                p.payload["status"] ?? "Working...",
                for: conversationId
            )
        } else if !hasExternalRawHandler {
            if rawType == RawEventType.todoWrite || p.payload.keys.contains(where: {
                $0.hasPrefix("todo_")
            }) {
                handleRawTodoWrite(p, for: conversationId)
            } else if envelopeContainsDebugEvent(normalizedEnvelope) {
                handleRawDebugEvent(
                    p,
                    normalizedEnvelope: normalizedEnvelope,
                    for: conversationId
                )
            } else if rawType == RawEventType.planStep {
                handleRawPlanStep(p, for: conversationId)
            } else {
                forwardRawEnvelopeToTaskActivity(
                    normalizedEnvelope,
                    for: conversationId
                )
            }
        } else if mainChatTraceLoggingEnabled() {
            NSLog(
                "[PipelineIntegration] skipped local raw side-effects because external raw handler consumed type=%@ conv=%@",
                rawType,
                conversationId.uuidString.lowercased()
            )
        } else {
            forwardRawEnvelopeToTaskActivity(
                normalizedEnvelope,
                for: conversationId
            )
        }

        // Applica subito eventi pipeline accodati dal debounce 16ms, così raw path + XCTest vedono stato coerente.
        if let chatStore,
           let runtime = runtime(for: conversationId),
           !runtime.pendingRustBridgeEvents.isEmpty {
            flushPendingRustBridgeEventsIfNeeded(
                conversationId: conversationId,
                runtime: runtime,
                chatStore: chatStore
            )
        }
    }

    func projectAssistantUpdateIntoPrimaryTextIfNeeded(
        rawEvent: RawEventPayload,
        providerId: String,
        conversationId: UUID
    ) {
        guard rawEvent.rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == RawEventType.assistantUpdate,
              let runtime = runtime(for: conversationId)
        else { return }
        let status = runtime.chatTurnState.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status != "completed", status != "failed" else {
            return
        }

        // Codex app-server: la fase `commentary` è instradata come testo principale (text_delta + assistant_update),
        // così la risposta visibile non resta solo nel blocco Thinking.

        let rawText = rawEvent.payload["output"] ?? rawEvent.payload["text"]
            ?? rawEvent.payload["content"] ?? rawEvent.payload["detail"] ?? ""
        let cleaned = ChatStore.stripCoderideMarkers(rawText, aggressive: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }
        if mainChatTraceLoggingEnabled() {
            NSLog(
                "[MainChatTrace] pipeline assistant_update project conv=%@ msg=%@ chars=%ld status=%@",
                conversationId.uuidString.lowercased(),
                runtime.assistantMessageId.uuidString.lowercased(),
                cleaned.count,
                status
            )
        }

        let streamId = rawEvent.taskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (runtime.chatTurnState.orderedTextStreamIds.first ?? "main")
            : rawEvent.taskId
        guard runtime.chatTurnState.textByStreamId[streamId]?.trimmingCharacters(in: .whitespacesAndNewlines) != cleaned else {
            return
        }


        consumePipelineEvents([ChatPipelineEvent(
            conversationId: conversationId,
            assistantMessageId: runtime.assistantMessageId,
            turnId: runtime.chatTurnState.turnId,
            sequence: 0,
            source: providerId,
            kind: .textReplace,
            payload: ["replacement": cleaned, "stream_id": streamId, "task_id": streamId, "provider_id": providerId]
        )], for: conversationId)
    }

    private func forwardRawEnvelopeToTaskActivity(
        _ envelope: NormalizedEventEnvelope,
        for conversationId: UUID
    ) {
        taskActivityStore?.addEnvelope(envelope)
        for event in envelope.events {
            if case .taskActivity(let activity) = event {
                taskActivityStore?.addActivity(
                    scopedTaskActivity(activity, conversationId: conversationId)
                )
            }
        }
    }

    private func normalizeRawEventEnvelope(_ payload: RawEventPayload) -> NormalizedEventEnvelope {
        EventNormalizer.normalizeEnvelope(
            sourceProvider: "pipeline",
            type: payload.rawType,
            payload: payload.payload
        )
    }

    private func envelopeContainsDebugEvent(_ envelope: NormalizedEventEnvelope) -> Bool {
        return envelope.events.contains(where: { DebugProjectionEventConsumer.handles($0) })
    }

    private func handleRawDebugEvent(
        _ p: RawEventPayload,
        normalizedEnvelope envelope: NormalizedEventEnvelope,
        for conversationId: UUID
    ) {
        taskActivityStore?.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                taskActivityStore?.addActivity(
                    scopedTaskActivity(activity, conversationId: conversationId)
                )
            default:
                guard DebugProjectionEventConsumer.handles(event) else { continue }
                applyOrBufferDebugEvent(event, for: conversationId)
            }
        }
    }

    private func scopedTaskActivity(
        _ activity: TaskActivity,
        conversationId: UUID
    ) -> TaskActivity {
        var payload = activity.payload
        payload["conversation_id"] = conversationId.uuidString
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

    // MARK: - Plan Build Finalization

    func finalizePlanBuild(
        agentConversationId: UUID,
        planConversationId planId: UUID,
        durationMs: Int,
        completedTasks: Int,
        totalTasks: Int
    ) {
        guard let todoStore else { return }

        let agentRuntime = runtime(for: agentConversationId)
        consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: agentConversationId,
                    assistantMessageId: agentRuntime?.assistantMessageId ?? UUID(),
                    turnId: agentRuntime?.chatTurnState.turnId ?? UUID().uuidString,
                    sequence: 0,
                    source: "pipeline",
                    kind: .statusBadge,
                    payload: [
                        "artifact_id": "plan-build-summary",
                        "title": "Plan build complete",
                        "detail": buildPlanRecap(
                            durationMs: durationMs,
                            completedTasks: completedTasks,
                            totalTasks: totalTasks
                        ),
                    ]
                ),
            ],
            for: agentConversationId
        )

        let canonicalTodos = todoStore.canonicalTodos(for: planId)
        chatStore?.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: planId)
    }

    private func buildPlanRecap(
        durationMs: Int,
        completedTasks: Int,
        totalTasks: Int
    ) -> String {
        let duration = formatDuration(durationMs)
        return "\n\n---\n**Plan Build Complete** (\(duration))"
            + "\n\(completedTasks)/\(totalTasks) tasks completed."
            + "\nPlease review the changes and run tests."
    }

    func handleProgress(_ p: ProgressPayload, for conversationId: UUID) {
        guard let runtime = runtime(for: conversationId) else { return }
        runtime.completedTasks = p.completedTasks
        runtime.totalTasks = p.totalTasks
        runtime.jobState = p.currentState
        persistSnapshot(for: conversationId)
    }

    func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remaining = Int(seconds) % 60
        return "\(minutes)m \(remaining)s"
    }
}
