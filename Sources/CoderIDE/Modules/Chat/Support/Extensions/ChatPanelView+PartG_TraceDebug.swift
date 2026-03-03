import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func autoTodoTitle(for activity: TaskActivity) -> String {
        let normalizedTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty, !isPlaceholderTodoTitle(normalizedTitle) {
            return normalizedTitle
        }
        if let path = activity.payload["path"] ?? activity.payload["file"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let base = (path as NSString).lastPathComponent
            return "Complete changes on \(base)"
        }
        if let query = activity.payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Complete analysis: \(String(query.prefix(80)))"
        }
        if let command = activity.payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Complete execution: \(String(command.prefix(80)))"
        }
        return "Complete the required operational steps"
    }

    internal func autoTodoLinkedFiles(from payload: [String: String]) -> [String] {
        var files = Set<String>()
        for candidate in [payload["path"], payload["file"], payload["files"]] {
            let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { continue }
            let splitItems = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if splitItems.isEmpty {
                files.insert(raw)
            } else {
                splitItems.forEach { files.insert($0) }
            }
        }
        return files.sorted()
    }

    internal func shouldAcceptTodoWrite(_ todo: TodoWritePayload, conversationId: UUID?) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return true
        }
        if isPlaceholderTodoTitle(todo.title) {
            return false
        }
        // Always accept updates when agent todos already exist (status changes, new items).
        let hasExistingAgentTodo = todoStore.todos.contains {
            $0.source == .agent && !$0.isPlanCanonical
        }
        if hasExistingAgentTodo {
            return true
        }
        // Accept the first TodoWrite in a turn even without prior operational activity.
        // The mandatory workflow is: investigate → report → create TODO → resolve.
        // The agent may create TODOs before or after operational activity; both are valid.
        if hasOperationalActivityInCurrentTurn(conversationId: conversationId) {
            return true
        }
        // Accept the first explicit todo for this assistant message, even without
        // operational activity. This ensures the TODO live activity appears when
        // the agent creates tasks after analysis (including subagent/swarm analysis).
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            // When conversationId or assistantMessageId is unavailable (e.g. during
            // swarm follow-up), accept the todo so the live activity is not silently lost.
            return true
        }
        return !didReceiveExplicitTodoByMessage.contains(assistantMessageId)
    }

    internal func shouldAcceptTodoRead(conversationId: UUID?) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return true
        }
        guard todoStore.todos.contains(where: { $0.source == .agent || $0.isPlanCanonical }) else {
            return false
        }
        return hasOperationalActivityInCurrentTurn(conversationId: conversationId)
    }

    internal func hasOperationalActivityInCurrentTurn(conversationId: UUID?) -> Bool {
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            return false
        }
        if let cached = toolTraceOperationalSeenByMessage[assistantMessageId] {
            return cached
        }
        let existing = toolTraceStore.events(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )
        let hasOperational = existing.contains { isOperationalTraceEvent($0) }
        toolTraceOperationalSeenByMessage[assistantMessageId] = hasOperational
        return hasOperational
    }

    internal func currentAssistantMessageIdForTrace(conversationId: UUID) -> UUID? {
        if let active = activeToolTraceTurnsByConversation[conversationId] {
            return active.assistantMessageId
        }
        return chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id
    }

    internal func isOperationalTraceActivity(_ activity: TaskActivity) -> Bool {
        guard ToolTraceVisibility.shouldDisplay(activity: activity) else { return false }
        let type = activity.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded: Set<String> = [
            "todo_read",
            "todo_write",
            "plan_step",
            "plan_step_update",
            "activate_plan_mode",
            "activate_debug_mode",
            "policy_ack",
        ]
        return !excluded.contains(type)
    }

    internal func isOperationalTraceEvent(_ event: ToolTraceEvent) -> Bool {
        guard ToolTraceVisibility.shouldDisplay(event: event) else { return false }
        let type = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded: Set<String> = [
            "todo_read",
            "todo_write",
            "plan_step",
            "plan_step_update",
            "activate_plan_mode",
            "activate_debug_mode",
            "policy_ack",
        ]
        return !excluded.contains(type)
    }

    internal func isPlaceholderTodoTitle(_ rawTitle: String) -> Bool {
        let normalized = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        let genericTitles: Set<String> = [
            "task",
            "tasks",
            "todo",
            "todos",
            "step",
            "steps",
            "analysis",
            "workflow",
            "execution",
            "plan",
        ]
        if genericTitles.contains(normalized) {
            return true
        }
        if normalized.range(of: #"^(task|step)\s*\d*$"#, options: .regularExpression) != nil {
            return true
        }
        if normalized.contains("task panel")
            || normalized.contains("todo update")
            || normalized.contains("turn started")
        {
            return true
        }
        return false
    }

    @MainActor
    internal func handleDebugPhaseUpdate(phase: DebugFlowPhase, detail: String?) {
        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }
        let previousPhase = debugStore.phase
        debugStore.setPhase(phase)
        let shouldClearQuestions = phase == .fixing
            || phase == .instrumenting
            || phase == .verifying
            || phase == .resolved
        if shouldClearQuestions, previousPhase != phase, !debugStore.clarificationQuestions.isEmpty {
            debugStore.clarificationQuestions = ""
        }
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debugStore.addLog(
                severity: .info,
                source: "debug_set_phase",
                message: "Phase → \(phase.label)",
                detail: detail,
                category: "system"
            )
        }
    }

    @MainActor
    internal func handleDebugUserRequest(kind: String, prompt: String) {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { return }

        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }

        switch normalizedKind {
        case "reproduce":
            if debugStore.phase == .idle || debugStore.phase == .describing {
                debugStore.setPhase(.reproducing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        default:
            if debugStore.phase == .idle {
                debugStore.setPhase(.describing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        }
    }

    @MainActor
    internal func handleDebugResolved(summary: String) {
        if debugStore.awaitingDebugClean {
            debugStore.addLog(
                severity: .warning,
                source: "debug_resolve",
                message: "Ignoring debug_resolve while waiting for debug_clean",
                category: "system"
            )
            return
        }
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        debugStore.resolveSession(
            summary: normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
        )
    }

    @MainActor
    internal func handleDebugLogPayload(_ payload: DebugLogToolPayload) {
        debugStore.addLog(
            severity: payload.severity,
            source: payload.source,
            message: payload.message,
            detail: payload.detail,
            category: payload.category
        )

        let isRuntimeLike = payload.category == "runtime"
            || payload.category == "instrumentation"
            || !payload.data.isEmpty
            || !(payload.hypothesisId ?? "").isEmpty
        if isRuntimeLike {
            debugStore.addRuntimeLog(
                location: payload.source,
                message: payload.message,
                data: payload.data,
                hypothesisId: payload.hypothesisId,
                runId: payload.runId
            )
        }
    }

    @MainActor
    internal func handleDebugHypothesizePayload(_ payload: DebugHypothesizeToolPayload) {
        switch payload.action {
        case "update":
            guard let hypothesisId = payload.hypothesisId,
                  let status = payload.status
            else {
                return
            }
            let updated = debugStore.updateHypothesis(id: hypothesisId, status: status, evidence: payload.evidence)
            if !updated {
                debugStore.addLog(
                    severity: .warning,
                    source: "debug_hypothesize",
                    message: "Hypothesis update ignored: unknown id",
                    detail: payload.hypothesisIdRaw,
                    category: "debug"
                )
            }
        default:
            let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let description = payload.description ?? ""
            let _ = debugStore.addHypothesis(
                id: payload.hypothesisId,
                title: title,
                description: description,
                status: payload.status ?? .proposed,
                evidence: payload.evidence
            )
        }
    }

    @MainActor
    internal func handleDebugMarkPayload(_ payload: DebugMarkToolPayload) {
        debugStore.addDebugMarker(DebugMarker(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            markerComment: payload.comment,
            originalContent: payload.originalContent
        ))
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    internal func handleDebugInstrumentPayload(_ payload: DebugInstrumentToolPayload) {
        let instrumentationType: InstrumentationPoint.InstrumentationType
        switch payload.type {
        case "assert":
            instrumentationType = .assertion
        case "timing":
            instrumentationType = .timing
        case "variable":
            instrumentationType = .variable
        default:
            instrumentationType = .logging
        }
        let displayLabel = payload.label?.isEmpty == false
            ? (payload.label ?? "")
            : (payload.expression ?? "instrumentation")
        debugStore.addInstrumentation(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            type: instrumentationType,
            code: displayLabel,
            hypothesisId: payload.hypothesisId
        )
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    internal func handleDebugCleanPayload(_ payload: DebugCleanToolPayload) {
        if payload.dryRun {
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_clean",
                    message: "Dry-run preview received (cleanup not applied)",
                    detail: detail,
                    category: "system"
                )
            }
            return
        }

        let normalizedStatus = (payload.status ?? "completed").lowercased()
        let cleanSucceeded = !(normalizedStatus == "failed" || normalizedStatus == "error")

        if debugStore.awaitingDebugClean {
            debugStore.applyDebugCleanResult(success: cleanSucceeded, detail: payload.detail)
            return
        }

        if cleanSucceeded {
            _ = debugStore.cleanAllDebugMarkers()
            _ = debugStore.cleanAllInstrumentation()
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(severity: .info, source: "debug_clean", message: detail, category: "system")
            }
        }
    }

    @MainActor
    internal func handleDebugSessionPayload(_ payload: DebugSessionToolPayload) {
        switch payload.action {
        case "start":
            if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
                debugStore.startDebugSession(errorContext: payload.detail ?? "")
            }
        case "clear":
            debugStore.resetSession()
        case "end", "stop":
            if debugStore.phase != .resolved {
                debugStore.setPhase(.verifying)
            }
        default:
            break
        }
    }

    @MainActor
    internal func handleDebugQueryPayload(_ payload: DebugQueryToolPayload) {
        let detail = payload.detail ?? "Debug query \(payload.format)"
        debugStore.addLog(
            severity: .info,
            source: "debug_query",
            message: detail,
            detail: payload.output,
            category: "debug"
        )
    }

    // MARK: - LLM Auto-Activation Handlers

    @MainActor
    internal func handleAutoActivatePlanMode(reason: String?) {
        // Skip if already in plan mode or a plan flow is actively running.
        guard coderMode != .plan else { return }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .building:
            return
        default:
            break
        }
        selectMode(.plan)
        planToggleEnabled = true
        if !showPlanPanel {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
    }

    @MainActor
    internal func handleAutoActivateDebugMode(reason: String?) {
        let normalizedReason = reason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if coderMode != .debug {
            selectMode(.debug)
        }
        if !showDebugPanel {
            debugToggleEnabled = true
            showDebugPanel = true
        } else {
            debugToggleEnabled = true
        }

        if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
            debugStore.startDebugSession(errorContext: normalizedReason ?? "")
            return
        }

        guard let normalizedReason, !normalizedReason.isEmpty else { return }
        if debugStore.errorSummary.isEmpty {
            debugStore.errorSummary = normalizedReason
        }
    }

    @MainActor
    internal func enqueueTaskActivity(_ activity: TaskActivity) {
        pendingTaskActivities.append(activity)
        logTaskBacklogIfNeeded(context: "enqueue_activity")

        let needsImmediateFlush = activity.type == "agent"
            || activity.isRunning
            || TaskActivityStore.isConcreteVisibleEventType(activity.type)
        if needsImmediateFlush {
            taskFlushTask?.cancel()
            taskFlushTask = nil
            flushPendingTaskActivities()

            // Fast-path: push the sidebar subtitle immediately so it
            // reflects the current tool without waiting for the
            // TaskActivityStore's internal 50ms coalescing buffer.
            if TaskActivityStore.isConcreteVisibleEvent(activity) {
                let label = Self.immediateSubtitleLabel(for: activity)
                if !label.isEmpty, let cid = conversationId {
                    chatStore.setTaskStatus(label, for: cid)
                }
            }
        } else {
            scheduleTaskActivityFlush()
        }
    }

}
