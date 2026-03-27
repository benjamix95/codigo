import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func buildAutoTodoTracePayload(
    todoId: UUID,
    title: String,
    status: TodoStatus,
    notes: String,
    linkedFiles: [String],
    conversationId: UUID?
) -> [String: String] {
    var payload: [String: String] = [
        "id": todoId.uuidString,
        "title": title,
        "task": title,
        "status": status.rawValue,
        "priority": TodoPriority.medium.rawValue,
        "notes": notes,
    ]
    if let conversationId {
        payload["conversation_id"] = conversationId.uuidString.lowercased()
    }
    if !linkedFiles.isEmpty {
        payload["files"] = linkedFiles.joined(separator: ",")
    }
    return payload
}

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
        let payload = buildAutoTodoTracePayload(
            todoId: todoId,
            title: title,
            status: status,
            notes: notes,
            linkedFiles: linkedFiles,
            conversationId: conversationId
        )

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
        let payloadConversationId = canonicalConversationScope(from: payload)
            .flatMap { UUID(uuidString: $0) }
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

    @MainActor
    internal func recordTaskActivity(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) {
        if mainChatTraceLoggingEnabled(),
           type == "assistant_update"
            || type == "command_execution"
            || type == "mcp_tool_call"
            || type == "turn_started"
            || type == "turn_completed"
        {
            NSLog(
                "[MainChatTrace] recordTaskActivity type=%@ provider=%@ conv=%@ title=%@ detail=%@ status=%@",
                type,
                providerId,
                conversationId?.uuidString.lowercased() ?? "-",
                payload["title"] ?? "-",
                payload["detail"] ?? "-",
                payload["status"] ?? "-"
            )
        }
        if SwarmMetadata.isSwarmEvent(payload)
            || type == "subagent_text"
            || type == "agent"
        {
            NSLog(
                "[SubagentPipe] normalize type=%@ swarm=%@ stage=%@ conv=%@ detail=%@",
                type,
                payload["swarm_id"] ?? payload["group_id"] ?? "-",
                payload["subagent_stage"] ?? "-",
                conversationId?.uuidString.lowercased() ?? "-",
                payload["detail"] ?? "-"
            )
        }
        cancelFallbackTurnStartEvent()
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)
        let planFallbackConversationId: UUID? = {
            guard let streamConversationId = conversationId else {
                return activeBuildPlanConversationId ?? chatStore.activeTaskConversationId
            }
            if let activeBuildAgentConversationId,
               let activeBuildPlanConversationId,
               streamConversationId == activeBuildAgentConversationId {
                return activeBuildPlanConversationId
            }
            return streamConversationId
        }()

        for event in envelope.events {
            if DebugProjectionEventConsumer.handles(event) {
                guard shouldRouteDebugProjectionEvent(event, debugToggleEnabled: debugToggleEnabled) else {
                    continue
                }
                routeDebugEvent(
                    event,
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
                continue
            }
            switch event {
            case .taskActivity(let activity):
                guard shouldDisplayTaskActivity(
                    type: activity.type,
                    debugToggleEnabled: debugToggleEnabled
                ) else {
                    continue
                }
                let scopedActivity = activityWithConversationContext(
                    activity,
                    conversationId: conversationId
                )
                ensureAutoTodoStartedBeforeOperationalActivity(
                    activity: scopedActivity,
                    providerId: providerId,
                    conversationId: conversationId
                )
                enqueueTaskActivity(scopedActivity)
                appendToolTraceEvent(
                    activity: scopedActivity,
                    rawKind: envelope.kind,
                    providerId: providerId,
                    conversationId: conversationId
                )
                updateAutoTodoProgressAfterOperationalActivity(
                    activity: scopedActivity,
                    providerId: providerId,
                    conversationId: conversationId
                )
            case .instantGrep(let grep):
                enableTaskPanelIfNeeded()
                let scopedGrep = instantGrepWithConversationContext(
                    grep,
                    conversationId: conversationId,
                    payload: envelope.payload
                )
                conversationRuntime.pendingInstantGreps.append(scopedGrep)
                logTaskBacklogIfNeeded(context: "enqueue_grep")
                scheduleTaskActivityFlush()
            case .todoWrite(let todo):
                handleTodoWriteEvent(
                    todo,
                    providerId: providerId,
                    conversationId: conversationId
                )
            case .todoRead:
                handleTodoReadEvent(conversationId: conversationId)
            case .planStepUpdate(let stepId, let status, let stepTitle):
                handleLegacyPlanStepUpdateEvent(
                    stepId: stepId,
                    status: status,
                    stepTitle: stepTitle,
                    conversationId: planFallbackConversationId
                )
            case .planCreate(let goal, let chosenPath, let steps, let planConversationId):
                handlePlanCreateEvent(
                    goal: goal,
                    chosenPath: chosenPath,
                    steps: steps,
                    eventConversationId: planConversationId,
                    fallbackConversationId: planFallbackConversationId
                )
            case .planRead:
                break
            case .planStepUpsert(let payload):
                handlePlanStepUpsertEvent(payload, fallbackConversationId: planFallbackConversationId)
            case .planStepBatchUpdate(let items, let planConversationId):
                handlePlanStepBatchUpdateEvent(
                    items: items,
                    conversationId: planConversationId,
                    fallbackConversationId: planFallbackConversationId
                )
            case .planStepReorder(let orderedStepIds, let planConversationId):
                handlePlanStepReorderEvent(
                    orderedStepIds: orderedStepIds,
                    conversationId: planConversationId,
                    fallbackConversationId: planFallbackConversationId
                )
            case .planStepDependencySet(let stepId, let dependsOn, let planConversationId):
                handlePlanStepDependencySetEvent(
                    stepId: stepId,
                    dependsOn: dependsOn,
                    conversationId: planConversationId,
                    fallbackConversationId: planFallbackConversationId
                )
            case .planSetWalkthrough(let markdown, let summary, let outcome, let planConversationId):
                handlePlanSetWalkthroughEvent(
                    markdown: markdown,
                    summary: summary,
                    outcome: outcome,
                    conversationId: planConversationId,
                    fallbackConversationId: planFallbackConversationId
                )
            case .planHistoryRead:
                break
            case .planDiff:
                break
            case .planRequestUserInput(let request):
                handlePlanRequestUserInputEvent(
                    request,
                    fallbackConversationId: planFallbackConversationId
                )
            case .activatePlanMode(let reason):
                handleAutoActivatePlanMode(reason: reason)
            case .mermaidRender(let code, let title):
                if let target = currentAssistantPipelineTarget(for: conversationId),
                   let conversationId
                {
                    applyChatPipelineEvent(
                        ChatPipelineEvent(
                            conversationId: conversationId,
                            assistantMessageId: target.messageId,
                            turnId: target.turnId,
                            sequence: 0,
                            source: providerId,
                            kind: .mermaidArtifact,
                            payload: [
                                "artifact_id": "mermaid-\(abs(code.hashValue))",
                                "code": code,
                                "title": title ?? "Diagram",
                                "provider_id": providerId,
                            ]
                        ),
                        persistImmediately: true
                    )
                }
                if shouldRoutePlanStream(to: conversationId) {
                    let titlePrefix = title.map { "**\($0)**\n\n" } ?? ""
                    let mermaidMarkdown = "\(titlePrefix)```mermaid\n\(code)\n```"
                    appendPlanStreamingContent(
                        mermaidMarkdown,
                        conversationId: conversationId
                    )
                    if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
                }
            default:
                break
            }
        }
    }

    internal func recordExplicitTodoWrite(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        conversationRuntime.didReceiveExplicitTodoByMessage.insert(messageId)
        applyAutoTodoRuntimeIntent(
            "auto_todo_discard_runtime",
            assistantMessageId: messageId,
            providerId: providerId,
            conversationId: turn.conversationId
        )
    }

    internal func ensureAutoTodoStartedBeforeOperationalActivity(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        startAutoTodoIfNeeded(
            activity: activity,
            providerId: providerId,
            conversationId: conversationId
        )
    }

    internal func updateAutoTodoProgressAfterOperationalActivity(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        refreshAutoTodoIfNeeded(
            activity: activity,
            providerId: providerId,
            conversationId: conversationId
        )
    }

}
