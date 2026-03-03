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
                guard shouldAcceptTodoWrite(todo, conversationId: conversationId) else { break }
                enableTaskPanelIfNeeded()
                if isPlanBuildContext(
                    conversationId: conversationId,
                    phase: planFlowPhase,
                    activeBuildPlanConversationId: activeBuildPlanConversationId,
                    activeBuildAgentConversationId: activeBuildAgentConversationId
                ) {
                    let sourcePlanId = activeBuildPlanConversationId ?? conversationId
                    let updated = todoStore.upsertCanonicalOnlyFromAgent(
                        id: todo.id,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        activeForm: todo.activeForm,
                        linkedFiles: todo.files,
                        conversationId: sourcePlanId
                    )
                    if updated {
                        if let sourcePlanId {
                            let canonicalTodos = todoStore.canonicalTodos(for: sourcePlanId)
                            chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: sourcePlanId)
                        }
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
            case .todoRead:
                guard shouldAcceptTodoRead(conversationId: conversationId) else { break }
                enableTaskPanelIfNeeded()
                break
            case .planStepUpdate(let stepId, let status, let stepTitle):
                let targetId = resolvePlanStepTargetConversationId(
                    eventConversationId: conversationId,
                    activeBuildPlanConversationId: activeBuildPlanConversationId,
                    activeTaskConversationId: chatStore.activeTaskConversationId
                )
                chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: targetId)
                if let sourcePlanId = activeBuildPlanConversationId, sourcePlanId != targetId {
                    chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: sourcePlanId)
                }
                // Cross-sync: PlanStep status → canonical TodoItem
                if let title = stepTitle {
                    let todoStatus: TodoStatus = {
                        switch status {
                        case .pending: return .pending
                        case .running: return .inProgress
                        case .done: return .done
                        case .failed: return .blocked
                        }
                    }()
                    let stepActiveForm: String? = status == .running ? title : nil
                    let targetCanonicalConversationId = activeBuildPlanConversationId ?? targetId
                    let updated = todoStore.upsertCanonicalOnlyFromAgent(
                        id: nil,
                        title: title,
                        status: todoStatus,
                        priority: nil,
                        notes: nil,
                        activeForm: stepActiveForm,
                        linkedFiles: [],
                        conversationId: targetCanonicalConversationId
                    )
                    if !updated,
                       !isPlanBuildContext(
                        conversationId: conversationId,
                        phase: planFlowPhase,
                        activeBuildPlanConversationId: activeBuildPlanConversationId,
                        activeBuildAgentConversationId: activeBuildAgentConversationId
                       ) {
                        todoStore.upsertFromAgent(
                            id: nil,
                            title: title,
                            status: todoStatus,
                            priority: nil,
                            notes: nil,
                            activeForm: stepActiveForm,
                            linkedFiles: [],
                            conversationId: conversationId
                        )
                    }
                }
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
