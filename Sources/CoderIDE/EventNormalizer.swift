import Foundation

struct TodoWritePayload {
    let id: UUID?
    let title: String
    let status: TodoStatus?
    let priority: TodoPriority?
    let notes: String?
    let activeForm: String?
    let files: [String]
}

struct DebugLogToolPayload {
    let severity: DebugEntrySeverity
    let source: String
    let message: String
    let detail: String?
    let category: String?
    let data: [String: String]
    let runId: String?
    let hypothesisId: String?
}

struct DebugHypothesizeToolPayload {
    let action: String
    let hypothesisId: UUID?
    let hypothesisIdRaw: String?
    let title: String?
    let description: String?
    let status: DebugHypothesis.HypothesisStatus?
    let evidence: String?
}

struct DebugMarkToolPayload {
    let filePath: String
    let lineNumber: Int
    let comment: String
    let originalContent: String?
}

struct DebugCleanToolPayload {
    let cleanedCount: Int
    let filesCount: Int
    let detail: String?
    let status: String?
}

struct DebugSessionToolPayload {
    let action: String
    let sessionId: String?
    let detail: String?
    let status: String?
}

struct DebugQueryToolPayload {
    let format: String
    let output: String?
    let detail: String?
    let status: String?
}

enum NormalizedEvent {
    case taskActivity(TaskActivity)
    case instantGrep(InstantGrepResult)
    case todoWrite(TodoWritePayload)
    case todoRead
    case planStepUpdate(stepId: String, status: PlanStepStatus, title: String?)
    case debugPhaseUpdate(phase: DebugFlowPhase, detail: String?)
    case debugUserRequest(kind: String, prompt: String)
    case debugResolved(summary: String)
    case debugLog(DebugLogToolPayload)
    case debugHypothesize(DebugHypothesizeToolPayload)
    case debugMark(DebugMarkToolPayload)
    case debugClean(DebugCleanToolPayload)
    case debugSession(DebugSessionToolPayload)
    case debugQuery(DebugQueryToolPayload)
    /// LLM requests to auto-activate plan mode panel
    case activatePlanMode(reason: String?)
    /// LLM requests to auto-activate debug mode panel
    case activateDebugMode(reason: String?)
    /// LLM requests to render a mermaid diagram in the IDE chat
    case mermaidRender(code: String, title: String?)
}

enum EventKind: String, Codable {
    case terminalSession = "terminal_session"
    case fileUpdate = "file_update"
    case instantGrep = "instant_grep"
    case todoUpdate = "todo_update"
    case planStepUpdate = "plan_step_update"
    case debugPhaseUpdate = "debug_phase_update"
    case debugUserRequest = "debug_user_request"
    case debugResolved = "debug_resolved"
    case debugToolUpdate = "debug_tool_update"
    case modeActivation = "mode_activation"
    case swarmProgress = "swarm_progress"
    case usageUpdate = "usage_update"
    case errorDiagnostic = "error_diagnostic"
    case mermaidRender = "mermaid_render"
    case generic = "generic"
}

struct NormalizedEventEnvelope {
    let version: Int
    let sourceProvider: String
    let timestamp: Date
    let kind: EventKind
    let payload: [String: String]
    let events: [NormalizedEvent]
}

enum EventNormalizer {
    static func normalizeEnvelope(
        sourceProvider: String,
        type: String,
        payload: [String: String],
        timestamp: Date = .now
    ) -> NormalizedEventEnvelope {
        let events = normalize(type: type, payload: payload, timestamp: timestamp)
        let kind: EventKind
        switch type {
        case "command_execution", "bash": kind = .terminalSession
        case "file_change", "edit",
             "str_replace", "regex_replace", "write", "write_file", "create_file", "delete_file",
             "parallel_apply", "apply_patch", "rename_symbol", "find_and_replace_all", "undo_edit",
             "multi_edit", "multiedit",
             "notebook_edit", "notebook_write":
            kind = .fileUpdate
        case "turn_started", "turn_completed": kind = .generic
        case "instant_grep", "search",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": kind = .instantGrep
        case "todo_write", "todo_read": kind = .todoUpdate
        case "plan_step", "plan_step_update": kind = .planStepUpdate
        case "mermaid_render": kind = .mermaidRender
        case "debug_phase_update": kind = .debugPhaseUpdate
        case "debug_user_request": kind = .debugUserRequest
        case "debug_resolved": kind = .debugResolved
        case "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean":
            kind = .debugToolUpdate
        case "debug_panel", "debug_panel_update":
            kind = .errorDiagnostic
        case "activate_plan_mode", "activate_debug_mode": kind = .modeActivation
        case "swarm_steps", "agent": kind = .swarmProgress
        case "usage": kind = .usageUpdate
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied", "error":
            kind = .errorDiagnostic
        default: kind = .generic
        }
        return NormalizedEventEnvelope(
            version: 1,
            sourceProvider: sourceProvider,
            timestamp: timestamp,
            kind: kind,
            payload: payload,
            events: events
        )
    }

    static func normalize(type: String, payload: [String: String], timestamp: Date = .now) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []
        if type == "reasoning" {
            return []
        }

        if type == "todo_write" {
            // Parse the full todos array when available (serialized as JSON by mapTodo).
            if let todosJson = payload["todos_json"],
               let todosData = todosJson.data(using: .utf8),
               let todosArray = try? JSONSerialization.jsonObject(with: todosData) as? [[String: Any]] {
                // Empty array is valid — means "clear todos" or "no-op"; skip batch processing
                guard !todosArray.isEmpty else {
                    return events
                }
                var summaryParts: [String] = []
                for todoItem in todosArray {
                    let content = (todoItem["content"] as? String ?? todoItem["title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !content.isEmpty else { continue }
                    let statusStr = todoItem["status"] as? String
                    let status = normalizedTodoStatus(statusStr)
                    var activeForm = (todoItem["activeForm"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Reject nested JSON objects accidentally passed as activeForm
                    if let af = activeForm, af.hasPrefix("{") || af.hasPrefix("[") {
                        activeForm = nil
                    }
                    let priorityStr = todoItem["priority"] as? String
                    let priority = normalizedTodoPriority(priorityStr)
                    let notes = (todoItem["notes"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let linkedFiles = (todoItem["linkedFiles"] as? [String])
                        ?? (todoItem["files"] as? [String])
                        ?? []
                    events.append(.todoWrite(TodoWritePayload(
                        id: nil,
                        title: content,
                        status: status,
                        priority: priority,
                        notes: notes,
                        activeForm: activeForm,
                        files: linkedFiles
                    )))
                    summaryParts.append(content)
                }
                if !events.isEmpty {
                    let detail = "\(summaryParts.count) tasks"
                    events.append(
                        .taskActivity(
                            TaskActivity(
                                type: type,
                                title: "Todo updated",
                                detail: detail,
                                payload: payload,
                                timestamp: timestamp,
                                phase: .planning,
                                isRunning: false
                            )
                        )
                    )
                    return events
                }
            }
            // Fallback: single todo item (legacy or simple payload)
            if let todo = parseTodoWrite(payload: payload) {
                events.append(.todoWrite(todo))
                events.append(
                    .taskActivity(
                        TaskActivity(
                            type: type,
                            title: "Todo updated",
                            detail: todo.title,
                            payload: payload,
                            timestamp: timestamp,
                            phase: .planning,
                            isRunning: false
                        )
                    )
                )
                return events
            }
        }
        if type == "todo_read" {
            events.append(.todoRead)
            events.append(
                .taskActivity(
                    TaskActivity(
                        type: type,
                        title: "Todo read",
                        detail: "Requested current task status",
                        payload: payload,
                        timestamp: timestamp,
                        phase: .planning,
                        isRunning: false
                    )
                )
            )
            return events
        }
        if (type == "plan_step" || type == "plan_step_update"),
           let stepId = payload["step_id"],
           let statusRaw = payload["status"] {
            let status: PlanStepStatus = {
                if let parsed = PlanStepStatus(rawValue: statusRaw) { return parsed }
                // Handle common LLM aliases
                let normalized = statusRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch normalized {
                case "completed", "complete", "finished", "success": return .done
                case "active", "doing", "started", "in_progress", "in-progress": return .running
                case "blocked", "error", "stuck": return .failed
                case "todo", "open", "queued", "waiting": return .pending
                default:
                    print("[EventNormalizer] ⚠️ Unknown plan step status '\(statusRaw)', defaulting to .pending")
                    return .pending
                }
            }()
            let stepTitle = payload["title"] ?? payload["detail"]
            events.append(.planStepUpdate(stepId: stepId, status: status, title: stepTitle))
            events.append(.taskActivity(TaskActivity(
                type: "plan_step_update",
                title: stepTitle ?? "Plan step updated",
                detail: payload["detail"] ?? "Status: \(status.rawValue)",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: status == .running,
                groupId: payload["group_id"] ?? stepId
            )))
            return events
        }

        if type == "mermaid_render" {
            let code = (payload["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty {
                let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                events.append(.mermaidRender(code: code, title: title))
                events.append(.taskActivity(TaskActivity(
                    type: "mermaid_render",
                    title: title ?? "Mermaid diagram",
                    detail: "Rendered diagram in IDE",
                    payload: payload,
                    timestamp: timestamp,
                    phase: .planning,
                    isRunning: false
                )))
            }
            return events
        }

        if type == "debug_phase_update" {
            let phaseValue = payload["phase"]
            let phase = debugFlowPhase(from: phaseValue) ?? .describing
            let detail = payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(.debugPhaseUpdate(phase: phase, detail: detail))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Debug phase • \(phase.label)",
                detail: detail,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: phase != .resolved
            )))
            return events
        }

        if type == "debug_user_request" {
            let kind = (payload["kind"] ?? "question")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let prompt = (
                payload["prompt"]
                    ?? payload["detail"]
                    ?? payload["message"]
                    ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return events }
            events.append(.debugUserRequest(kind: kind, prompt: prompt))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: kind == "reproduce" ? "Debug request • reproduce" : "Debug request • question",
                detail: prompt,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            )))
            return events
        }

        if type == "debug_resolved" {
            let summary = (
                payload["summary"]
                    ?? payload["detail"]
                    ?? payload["message"]
                    ?? "Debug session resolved"
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(.debugResolved(summary: summary.isEmpty ? "Debug session resolved" : summary))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Debug resolved",
                detail: summary,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            )))
            return events
        }

        if type == "debug_panel" || type == "debug_panel_update" {
            let detail = payload["detail"] ?? "Use debug_set_phase, debug_request_user, debug_resolve"
            events.append(.taskActivity(TaskActivity(
                type: "tool_validation_error",
                title: "Legacy debug_panel is not supported",
                detail: detail,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            )))
            return events
        }

        if type == "debug_log" {
            if let debugLogPayload = parseDebugLogPayload(payload: payload) {
                events.append(.debugLog(debugLogPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["message"] ?? payload["detail"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "debug_hypothesize" {
            if let hypothesisPayload = parseDebugHypothesizePayload(payload: payload) {
                events.append(.debugHypothesize(hypothesisPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["detail"] ?? payload["status"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "debug_mark" {
            if let markerPayload = parseDebugMarkPayload(payload: payload) {
                events.append(.debugMark(markerPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["detail"] ?? payload["marker_info"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "debug_clean" {
            if let cleanPayload = parseDebugCleanPayload(payload: payload) {
                events.append(.debugClean(cleanPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["detail"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "debug_session" {
            if let sessionPayload = parseDebugSessionPayload(payload: payload) {
                events.append(.debugSession(sessionPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["detail"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "debug_query" {
            if let queryPayload = parseDebugQueryPayload(payload: payload) {
                events.append(.debugQuery(queryPayload))
            }
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: payload["title"] ?? defaultTitle(for: type),
                detail: payload["detail"],
                payload: payload,
                timestamp: timestamp,
                phase: phaseForType(type, payload: payload),
                isRunning: runningStateForType(type, payload: payload),
                groupId: payload["group_id"] ?? payload["tool_call_id"]
            )))
            return events
        }

        if type == "activate_plan_mode" {
            let reason = payload["reason"]
            events.append(.activatePlanMode(reason: reason))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Plan mode auto-activated",
                detail: reason,
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            )))
            return events
        }

        if type == "activate_debug_mode" {
            let reason = payload["reason"]
            events.append(.activateDebugMode(reason: reason))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Debug mode auto-activated",
                detail: reason,
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: false
            )))
            return events
        }

        if type == "instant_grep", let grep = parseInstantGrep(payload: payload, timestamp: timestamp) {
            events.append(.instantGrep(grep))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Instant Grep • \(grep.query)",
                detail: "\(grep.matchesCount) results",
                payload: payload,
                timestamp: timestamp,
                phase: .searching,
                isRunning: false
            )))
            return events
        }

        if (type == "command_execution" || type == "bash"), let grep = parseInstantGrepFromCommand(payload: payload, timestamp: timestamp) {
            events.append(.instantGrep(grep))
        }
        if (type == "command_execution" || type == "bash"),
           let syntheticRead = parseReadActivityFromCommand(payload: payload, timestamp: timestamp) {
            events.append(.taskActivity(syntheticRead))
        }

        let normalizedType = normalizeSpecialType(type, payload: payload)
        let phase = phaseForType(normalizedType, payload: payload)
        let running = runningStateForType(normalizedType, payload: payload)
        let resolvedTitleDetail: (title: String, detail: String?) = {
            if normalizedType == "mcp_tool_call", isTrustedMCPPayload(payload) {
                return mcpTitleAndDetail(payload: payload)
            }
            return (payload["title"] ?? defaultTitle(for: normalizedType), payload["detail"])
        }()
        events.append(.taskActivity(TaskActivity(
            type: normalizedType,
            title: withSwarmPrefix(resolvedTitleDetail.title, payload: payload),
            detail: resolvedTitleDetail.detail,
            payload: payload,
            timestamp: timestamp,
            phase: phase,
            isRunning: running,
            groupId: payload["group_id"] ?? payload["queryId"] ?? payload["tool_call_id"]
        )))
        return events
    }

    private static func normalizeSpecialType(_ type: String, payload: [String: String]) -> String {
        let normalized = type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "mcp_tool_call", !isTrustedMCPPayload(payload) {
            return "command_execution"
        }
        let normalizedCanonicalType = normalizedToolIdentifier(normalized)
        if [
            "semantic_search", "read_lints", "debug_context",
            "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
            "debug_phase_update", "debug_user_request", "debug_resolved",
        ].contains(normalizedCanonicalType) {
            return normalizedCanonicalType
        }
        if fileChangeLikeTypes.contains(normalized) {
            return "file_change"
        }
        if type == "read_batch_completed",
           let rawToolName = payload["tool"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           [
               "semantic_search", "read_lints", "debug_context",
               "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean",
               "debug_phase_update", "debug_user_request", "debug_resolved",
           ].contains(normalizedToolIdentifier(rawToolName))
        {
            return normalizedToolIdentifier(rawToolName)
        }
        if type == "web_search",
           let status = payload["status"]?.lowercased() {
            switch status {
            case "started": return "web_search_started"
            case "completed": return "web_search_completed"
            case "failed": return "web_search_failed"
            default: break
            }
        }
        if type == "web_fetch",
           let status = payload["status"]?.lowercased() {
            switch status {
            case "started": return "web_fetch_started"
            case "completed": return "web_fetch_completed"
            case "failed": return "web_fetch_failed"
            default: break
            }
        }
        return type
    }

    private static func normalizedToolIdentifier(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else { return "" }
        let parts = normalized
            .split(whereSeparator: { ch in
                ch == "." || ch == ":" || ch == "/" || ch == "\\"
            })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return normalized }
        return last
    }

    private static func phaseForType(_ type: String, payload _: [String: String]) -> ActivityPhase {
        switch type {
        case "command_execution", "bash":
            return .executing
        case "mcp_tool_call":
            return .executing
        case "semantic_search":
            return .searching
        case "read_lints", "debug_context", "debug_log", "debug_query", "debug_session", "debug_hypothesize",
             "debug_phase_update", "debug_user_request", "debug_resolved":
            return .executing
        case "debug_mark", "debug_clean":
            return .editing
        case "file_change", "edit",
             "str_replace", "regex_replace", "write", "create_file", "delete_file",
             "parallel_apply", "rename_symbol", "find_and_replace_all", "undo_edit",
             "multi_edit", "multiedit",
             "read_batch_started", "read_batch_completed":
            return .editing
        case "turn_started", "turn_completed":
            return .planning
        case "process_paused":
            return .planning
        case "process_resumed":
            return .executing
        case "instant_grep", "search",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed":
            return .searching
        case "plan_step", "plan_step_update":
            return .planning
        case "policy_ack":
            return .planning
        default:
            return .planning
        }
    }

    private static func runningStateForType(_ type: String, payload: [String: String]) -> Bool {
        let status = payload["status"]?.lowercased()
        switch type {
        case "command_execution", "bash":
            return status == "started" || status == "running" || status == "in_progress"
        case "mcp_tool_call":
            return status == "started" || status == "running" || status == "in_progress"
        case "file_change":
            return status == "started" || status == "running" || status == "in_progress"
        case "agent":
            let detail = payload["detail"]?.lowercased()
            return detail == "started" || status == "started" || status == "running"
        case "turn_started":
            return true
        case "turn_completed":
            return false
        case "web_search_started", "web_fetch_started", "read_batch_started", "process_resumed":
            return true
        case "web_search_completed", "web_search_failed", "web_fetch_completed", "web_fetch_failed", "read_batch_completed", "process_paused":
            return false
        case "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean":
            return status == "started" || status == "running" || status == "in_progress"
        case "debug_phase_update":
            let normalizedPhase = (payload["phase"] ?? "").lowercased()
            return normalizedPhase != "resolved"
        default:
            return false
        }
    }

    private static func defaultTitle(for type: String) -> String {
        switch type {
        case "process_paused":
            return "Process paused"
        case "process_resumed":
            return "Process resumed"
        case "read_batch_started":
            return "File batch read started"
        case "read_batch_completed":
            return "File batch read completed"
        case "turn_started":
            return "Turn started"
        case "turn_completed":
            return "Turn completed"
        case "web_search_started":
            return "Web search started"
        case "web_search_completed":
            return "Web search completed"
        case "web_search_failed":
            return "Web search failed"
        case "web_fetch_started":
            return "Fetching web page"
        case "web_fetch_completed":
            return "Web page fetched"
        case "web_fetch_failed":
            return "Web fetch failed"
        case "tool_execution_error":
            return "Tool execution error"
        case "tool_validation_error":
            return "Tool validation error"
        case "tool_timeout":
            return "Timeout tool"
        case "permission_denied":
            return "Permission denied"
        case "debug_log":
            return "Debug log"
        case "debug_query":
            return "Debug query"
        case "debug_session":
            return "Debug session"
        case "debug_hypothesize":
            return "Debug hypothesis"
        case "debug_mark":
            return "Debug marker"
        case "debug_clean":
            return "Debug clean"
        case "debug_phase_update":
            return "Debug phase update"
        case "debug_user_request":
            return "Debug user request"
        case "debug_resolved":
            return "Debug resolved"
        case "policy_ack":
            return "Policy acknowledged"
        default:
            return type
        }
    }

    private static func debugFlowPhase(from raw: String?) -> DebugFlowPhase? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let phase = DebugFlowPhase(rawValue: normalized) {
            return phase
        }
        switch normalized {
        case "analyze", "analysis", "analyzing", "describe":
            return .describing
        case "reproduce":
            return .reproducing
        case "fix":
            return .fixing
        case "instrument":
            return .instrumenting
        case "verify":
            return .verifying
        case "resolve":
            return .resolved
        default:
            return nil
        }
    }

    private static func mcpTitleAndDetail(payload: [String: String]) -> (title: String, detail: String?) {
        guard isTrustedMCPPayload(payload) else {
            return (payload["title"] ?? "MCP operation", payload["detail"])
        }
        let rawTool = (payload["tool"] ?? payload["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tool = rawTool.lowercased()
        let server = (payload["mcp_server"] ?? payload["server_id"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mcpTool = (payload["mcp_tool"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = payload["detail"]

        switch tool {
        case "mcp_list_servers":
            return ("MCP discovery • servers", detail ?? "Checking available MCP servers")
        case "mcp_list_tools":
            if !server.isEmpty {
                return ("MCP discovery • tools", detail ?? "Listing tools on \(server)")
            }
            return ("MCP discovery • tools", detail ?? "Listing tools on all MCP servers")
        case "mcp_describe_tool":
            let target = !mcpTool.isEmpty ? mcpTool : "tool"
            return ("MCP inspect • \(target)", detail ?? "Inspecting tool schema")
        case "mcp_health":
            return ("MCP health check", detail ?? "Checking server health")
        case "mcp_reconnect":
            let target = server.isEmpty ? "server" : server
            return ("MCP reconnect • \(target)", detail ?? "Reconnecting MCP server")
        default:
            let isMCPLikeTool = !mcpTool.isEmpty || !server.isEmpty || isTrustedMCPPayload(payload)
            if isMCPLikeTool {
                var target = !mcpTool.isEmpty ? mcpTool : rawTool
                if target.isEmpty { target = "tool" }
                if !server.isEmpty {
                    return ("MCP call • \(server)/\(target)", detail)
                }
                return ("MCP call • \(target)", detail)
            }
            return (payload["title"] ?? "MCP operation", detail)
        }
    }

    private static let fileChangeLikeTypes: Set<String> = [
        "file_change",
        "edit",
        "str_replace",
        "regex_replace",
        "write",
        "create_file",
        "delete_file",
        "parallel_apply",
        "apply_patch",
        "rename_symbol",
        "find_and_replace_all",
        "undo_edit",
        "multi_edit",
        "multiedit",
        "write_file",
        "notebook_edit",
        "notebook_write",
    ]

    private static func isTrustedMCPPayload(_ payload: [String: String]) -> Bool {
        let marker = (payload["is_mcp"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if marker == "true" || marker == "1" || marker == "yes" {
            return true
        }
        if !(payload["mcp_tool"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !(payload["mcp_server"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        if !(payload["server_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private static func withSwarmPrefix(_ title: String, payload: [String: String]) -> String {
        guard let swarmId = SwarmMetadata.swarmId(from: payload) else {
            return title
        }
        if title.hasPrefix("Swarm \(swarmId)") {
            return title
        }
        return "Swarm \(swarmId) • \(title)"
    }

    private static func parseTodoWrite(payload: [String: String]) -> TodoWritePayload? {
        let title = (
            payload["title"]
                ?? payload["task"]
                ?? payload["name"]
                ?? payload["item"]
                ?? payload["detail"]
                ?? payload["summary"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let id = payload["id"].flatMap(UUID.init(uuidString:))
        let status = normalizedTodoStatus(payload["status"])
        let priority = normalizedTodoPriority(payload["priority"])
        let notes = payload["notes"]
        let activeForm = payload["activeForm"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = payload["files"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        return TodoWritePayload(id: id, title: title, status: status, priority: priority, notes: notes, activeForm: activeForm, files: files)
    }

    private static func normalizedTodoStatus(_ raw: String?) -> TodoStatus? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if let direct = TodoStatus(rawValue: normalized) { return direct }
        // Handle common LLM aliases
        switch normalized {
        case "completed", "complete", "finished": return .done
        case "running", "active", "doing", "started": return .inProgress
        case "todo", "open", "queued", "waiting": return .pending
        case "failed", "error", "stuck": return .blocked
        default: return nil
        }
    }

    private static func normalizedTodoPriority(_ raw: String?) -> TodoPriority? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return TodoPriority(rawValue: normalized)
    }

    private static func parseDebugLogPayload(payload: [String: String]) -> DebugLogToolPayload? {
        let severity = normalizeDebugSeverity(payload["severity"])
        let source = payload["source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "agent"
        let message = payload["message"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !message.isEmpty else { return nil }
        let data = parseDebugData(payload["data"]) 
        return DebugLogToolPayload(
            severity: severity,
            source: source,
            message: message,
            detail: payload["log_detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: payload["category"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            data: data,
            runId: payload["run_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            hypothesisId: payload["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDebugHypothesizePayload(payload: [String: String]) -> DebugHypothesizeToolPayload? {
        let action = (payload["action"] ?? "propose")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let hypothesisIdRaw = payload["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DebugHypothesizeToolPayload(
            action: action,
            hypothesisId: hypothesisIdRaw.flatMap(UUID.init(uuidString:)),
            hypothesisIdRaw: hypothesisIdRaw,
            title: payload["hypothesis_title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: payload["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: normalizeHypothesisStatus(payload["hypothesis_status"] ?? payload["status"]),
            evidence: payload["evidence"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDebugMarkPayload(payload: [String: String]) -> DebugMarkToolPayload? {
        let originalContent = payload["original_content"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerInfo = payload["marker_info"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !markerInfo.isEmpty {
            let parts = markerInfo.split(separator: "|", maxSplits: 2).map(String.init)
            if parts.count >= 2, let lineNumber = Int(parts[1]) {
                return DebugMarkToolPayload(
                    filePath: parts[0],
                    lineNumber: lineNumber,
                    comment: parts.count > 2 ? parts[2] : "debug marker",
                    originalContent: originalContent
                )
            }
        }

        let filePath = payload["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = Int(payload["line"] ?? "")
        guard !filePath.isEmpty, let line else { return nil }
        let comment = payload["comment"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "debug marker"
        return DebugMarkToolPayload(filePath: filePath, lineNumber: line, comment: comment, originalContent: originalContent)
    }

    private static func parseDebugCleanPayload(payload: [String: String]) -> DebugCleanToolPayload? {
        let status = payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCount = Int(payload["cleaned_markers"] ?? "") ?? 0
        let filesCount = Int(payload["cleaned_files"] ?? "") ?? 0
        if cleanedCount == 0, filesCount == 0,
           (payload["detail"] ?? "").isEmpty,
           (status ?? "").isEmpty {
            return nil
        }
        return DebugCleanToolPayload(
            cleanedCount: cleanedCount,
            filesCount: filesCount,
            detail: payload["detail"],
            status: status
        )
    }

    private static func parseDebugSessionPayload(payload: [String: String]) -> DebugSessionToolPayload? {
        let action = payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if action.isEmpty, payload["session_id"] == nil, payload["detail"] == nil { return nil }
        return DebugSessionToolPayload(
            action: action,
            sessionId: payload["session_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: payload["detail"],
            status: payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDebugQueryPayload(payload: [String: String]) -> DebugQueryToolPayload? {
        let format = payload["format"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "summary"
        if payload["detail"] == nil, payload["output"] == nil, payload["status"] == nil {
            return nil
        }
        return DebugQueryToolPayload(
            format: format,
            output: payload["output"],
            detail: payload["detail"],
            status: payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseDebugData(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in json {
                out[key] = "\(value)"
            }
            return out
        }
        let pairs = raw.split(separator: ",")
        var out: [String: String] = [:]
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].trimmingCharacters(in: .whitespacesAndNewlines)] = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return out
    }

    private static func normalizeDebugSeverity(_ raw: String?) -> DebugEntrySeverity {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error": return .error
        case "warning": return .warning
        case "verbose": return .verbose
        case "trace": return .trace
        default: return .info
        }
    }

    private static func normalizeHypothesisStatus(_ raw: String?) -> DebugHypothesis.HypothesisStatus? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed": return .proposed
        case "investigating": return .investigating
        case "confirmed": return .confirmed
        case "rejected": return .rejected
        default: return nil
        }
    }

    private static func parseInstantGrep(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let query = payload["query"], !query.isEmpty else { return nil }
        let scope = payload["pathScope"] ?? payload["scope"] ?? "."
        let matchesCount = Int(payload["matchesCount"] ?? "") ?? 0
        let durationMs = Int(payload["duration_ms"] ?? "")
        let preview = payload["previewLines"] ?? ""
        let parsedMatches = parseMatchLines(from: preview)
        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: max(matchesCount, parsedMatches.count),
            durationMs: durationMs,
            matches: parsedMatches,
            createdAt: timestamp
        )
    }

    private static func parseInstantGrepFromCommand(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let command = payload["command"] else { return nil }
        let lowered = command.lowercased()
        let hasRG = lowered.hasPrefix("rg ") || lowered.contains(" rg ")
        let hasGrep = lowered.hasPrefix("grep ") || lowered.contains(" grep ")
        guard hasRG || hasGrep else { return nil }
        let query = parseSearchQueryFromCommand(command) ?? "(query)"
        let scope = payload["cwd"] ?? "."
        let output = payload["output"] ?? ""
        let matches = parseMatchLines(from: output)
        guard !matches.isEmpty else { return nil }
        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: matches.count,
            durationMs: nil,
            matches: Array(matches.prefix(30)),
            createdAt: timestamp
        )
    }

    private static func parseReadActivityFromCommand(payload: [String: String], timestamp: Date) -> TaskActivity? {
        guard let command = payload["command"] else { return nil }
        let lower = command.lowercased()
        guard lower.contains("cat ")
            || lower.contains("sed -n")
            || lower.contains("head ")
            || lower.contains("tail ")
        else { return nil }

        guard let path = extractReadPath(from: command), !path.isEmpty else { return nil }
        let title = "Read • \((path as NSString).lastPathComponent)"
        return TaskActivity(
            type: "read_batch_completed",
            title: title,
            detail: path,
            payload: [
                "title": title,
                "detail": path,
                "path": path,
                "file": path,
                "count": "1",
                "files": path,
                "status": "completed",
                "source": "synthetic_command_read",
            ],
            timestamp: timestamp,
            phase: .editing,
            isRunning: false
        )
    }

    private static func parseMatchLines(from output: String) -> [InstantGrepMatch] {
        let lines = output.split(separator: "\n").map(String.init)
        var matches: [InstantGrepMatch] = []

        for line in lines.prefix(200) {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let file = String(parts[0])
            guard let number = Int(parts[1]) else { continue }
            let preview = String(parts[2]).trimmingCharacters(in: .whitespaces)
            matches.append(InstantGrepMatch(file: file, line: number, preview: preview))
        }
        return matches
    }

    private static func parseSearchQueryFromCommand(_ command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        if let rgIndex = tokens.firstIndex(where: { $0 == "rg" || $0.hasSuffix("/rg") || $0 == "grep" || $0.hasSuffix("/grep") }) {
            for token in tokens.dropFirst(rgIndex + 1) {
                if token.hasPrefix("-") { continue }
                return token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    private static func extractReadPath(from command: String) -> String? {
        let patterns = [
            #"(?:^|\s)(?:cat|head|tail)\s+(?:-[^\s]+\s+)*['"]?([^'" \t\n]+)['"]?"#,
            #"(?:^|\s)sed\s+-n\s+['"][^'"]+['"]\s+['"]?([^'" \t\n]+)['"]?"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let ns = command as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: command, options: [], range: range), match.numberOfRanges > 1 {
                let valueRange = match.range(at: 1)
                if valueRange.location != NSNotFound {
                    let value = ns.substring(with: valueRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        return value
                    }
                }
            }
        }
        return nil
    }
}
