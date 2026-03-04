import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func recordTaskActivity(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) {
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
            switch event {
            case .taskActivity(let activity):
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
                pendingInstantGreps.append(grep)
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
            case .debugPhaseUpdate(let phase, let detail):
                routeDebugEvent(
                    .debugPhaseUpdate(phase: phase, detail: detail),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugUserRequest(let kind, let prompt):
                routeDebugEvent(
                    .debugUserRequest(kind: kind, prompt: prompt),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugResolved(let summary):
                routeDebugEvent(
                    .debugResolved(summary: summary),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugLog(let payload):
                routeDebugEvent(
                    .debugLog(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugHypothesize(let payload):
                routeDebugEvent(
                    .debugHypothesize(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugMark(let payload):
                routeDebugEvent(
                    .debugMark(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugInstrument(let payload):
                routeDebugEvent(
                    .debugInstrument(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugClean(let payload):
                routeDebugEvent(
                    .debugClean(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugSession(let payload):
                routeDebugEvent(
                    .debugSession(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .debugQuery(let payload):
                routeDebugEvent(
                    .debugQuery(payload),
                    payload: envelope.payload,
                    eventConversationId: conversationId
                )
            case .activatePlanMode(let reason):
                handleAutoActivatePlanMode(reason: reason)
            case .activateDebugMode(let reason):
                handleAutoActivateDebugMode(reason: reason)
            case .mermaidRender(let code, let title):
                let titlePrefix = title.map { "**\($0)**\n\n" } ?? ""
                let mermaidMarkdown = "\(titlePrefix)```mermaid\n\(code)\n```"
                if shouldRoutePlanStream(to: conversationId) {
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
                } else {
                    // Non-plan flows keep the diagram in chat.
                    chatStore.updateLastAssistantMessage(
                        content: mermaidMarkdown,
                        in: conversationId,
                        persistImmediately: true
                    )
                }
            }
        }
    }

    internal func recordExplicitTodoWrite(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        didReceiveExplicitTodoByMessage.insert(messageId)
        if let autoTodoId = autoTodoIdByMessage[messageId] {
            todoStore.remove(id: autoTodoId)
            autoTodoIdByMessage.removeValue(forKey: messageId)
            autoTodoCompletedOperationsByMessage.removeValue(forKey: messageId)
        }
    }

    internal func ensureAutoTodoStartedBeforeOperationalActivity(
        activity _: TaskActivity,
        providerId _: String,
        conversationId _: UUID?
    ) {
        // Disabled: auto-TODO created placeholder items with generic titles
        // before the LLM had analyzed the task. Only explicit todo_write
        // events from the LLM should create TODOs.
    }

    internal func updateAutoTodoProgressAfterOperationalActivity(
        activity _: TaskActivity,
        providerId _: String,
        conversationId _: UUID?
    ) {
        // Disabled: auto-TODO progress updates are no longer needed
        // since auto-TODO creation is disabled.
    }

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

}
