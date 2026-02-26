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

enum NormalizedEvent {
    case taskActivity(TaskActivity)
    case instantGrep(InstantGrepResult)
    case todoWrite(TodoWritePayload)
    case todoRead
    case planStepUpdate(stepId: String, status: PlanStepStatus, title: String?)
    case debugPanelUpdate(action: String, phase: String?)
    /// LLM requests to auto-activate plan mode panel
    case activatePlanMode(reason: String?)
    /// LLM requests to auto-activate debug mode panel
    case activateDebugMode(reason: String?)
}

enum EventKind: String, Codable {
    case terminalSession = "terminal_session"
    case fileUpdate = "file_update"
    case instantGrep = "instant_grep"
    case todoUpdate = "todo_update"
    case planStepUpdate = "plan_step_update"
    case debugPanelUpdate = "debug_panel_update"
    case modeActivation = "mode_activation"
    case swarmProgress = "swarm_progress"
    case usageUpdate = "usage_update"
    case errorDiagnostic = "error_diagnostic"
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
             "str_replace", "regex_replace", "write", "create_file", "delete_file",
             "parallel_apply", "rename_symbol", "find_and_replace_all", "undo_edit",
             "multi_edit", "multiedit":
            kind = .fileUpdate
        case "turn_started", "turn_completed": kind = .generic
        case "instant_grep", "search",
             "web_search", "web_search_started", "web_search_completed", "web_search_failed",
             "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": kind = .instantGrep
        case "todo_write", "todo_read": kind = .todoUpdate
        case "plan_step", "plan_step_update": kind = .planStepUpdate
        case "debug_panel", "debug_panel_update": kind = .debugPanelUpdate
        case "activate_plan_mode", "activate_debug_mode": kind = .modeActivation
        case "swarm_steps", "agent": kind = .swarmProgress
        case "usage": kind = .usageUpdate
        case "error": kind = .errorDiagnostic
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
               let todosArray = try? JSONSerialization.jsonObject(with: todosData) as? [[String: Any]],
               !todosArray.isEmpty {
                var summaryParts: [String] = []
                for todoItem in todosArray {
                    let content = (todoItem["content"] as? String ?? todoItem["title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !content.isEmpty else { continue }
                    let statusStr = todoItem["status"] as? String
                    let status = normalizedTodoStatus(statusStr)
                    let activeForm = (todoItem["activeForm"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
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
           let statusRaw = payload["status"],
           let status = PlanStepStatus(rawValue: statusRaw) {
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

        if type == "debug_panel" || type == "debug_panel_update" {
            let action = payload["action"] ?? "open"
            let phase = payload["phase"]
            events.append(.debugPanelUpdate(action: action, phase: phase))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Debug: \(action)",
                detail: phase.map { "Phase: \($0)" },
                payload: payload,
                timestamp: timestamp,
                phase: .executing,
                isRunning: action != "close"
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
            if normalizedType == "mcp_tool_call" {
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
        let normalizedCanonicalType = normalizedToolIdentifier(normalized)
        if ["semantic_search", "read_lints", "debug_context"].contains(normalizedCanonicalType) {
            return normalizedCanonicalType
        }
        if fileChangeLikeTypes.contains(normalized) {
            return "file_change"
        }
        if type == "read_batch_completed",
           let rawToolName = payload["tool"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           ["semantic_search", "read_lints", "debug_context"].contains(
               normalizedToolIdentifier(rawToolName)
           ) {
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
        case "read_lints", "debug_context":
            return .executing
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
        case "debug_panel", "debug_panel_update":
            return .executing
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
        case "policy_ack":
            return "Policy acknowledged"
        default:
            return type
        }
    }

    private static func mcpTitleAndDetail(payload: [String: String]) -> (title: String, detail: String?) {
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
            let isMCPLikeTool = tool.hasPrefix("mcp")
                || !mcpTool.isEmpty
                || !server.isEmpty
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
    ]

    private static func withSwarmPrefix(_ title: String, payload: [String: String]) -> String {
        guard let swarmId = payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !swarmId.isEmpty else {
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
        return TodoStatus(rawValue: normalized)
    }

    private static func normalizedTodoPriority(_ raw: String?) -> TodoPriority? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return TodoPriority(rawValue: normalized)
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
