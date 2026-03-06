import Foundation

// MARK: - IDEStateSyntheticEvent

struct IDEStateSyntheticEvent: Sendable, Equatable {
    let type: String
    let payload: [String: String]
}

// MARK: - IDEStateSyntheticEventFactory

enum IDEStateSyntheticEventFactory {
    static let supportedTools: Set<String> = [
        "todo_write", "todo_read",
        "plan_step_update", "plan_step",
        "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_history_read", "plan_diff", "plan_request_user_input",
        "debug_set_phase", "debug_request_user", "debug_resolve",
        "policy_ack", "mermaid_render",
        "activate_plan_mode", "activate_debug_mode",
        "show_task_panel", "show_swarm_panel",
    ]

    static let legacyRemovedTools: Set<String> = [
        "debug_panel", "debug_panel_update",
    ]

    static let failureStatuses: Set<String> = [
        "failed", "error", "cancelled", "canceled", "aborted",
        "timeout", "timed_out",
    ]

    static func normalizeTool(_ rawTool: String) -> String {
        var normalized = rawTool
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        if normalized.hasPrefix("functions.") {
            normalized = String(normalized.dropFirst("functions.".count))
        }
        if normalized.hasPrefix("function.") {
            normalized = String(normalized.dropFirst("function.".count))
        }
        if normalized.hasPrefix("mcp__"),
           let namespaceSeparator = normalized.range(of: "__", options: .backwards) {
            let candidate = String(normalized[namespaceSeparator.upperBound...])
            if !candidate.isEmpty {
                normalized = candidate
            }
        }
        if let suffix = normalized.split(whereSeparator: { separator in
            separator == "." || separator == "/" || separator == ":" || separator == "\\"
        }).last {
            normalized = String(suffix)
        }
        while normalized.contains("__") {
            normalized = normalized.replacingOccurrences(of: "__", with: "_")
        }
        if normalized.hasPrefix("coderide_") {
            normalized = String(normalized.dropFirst("coderide_".count))
        }
        return normalized
    }

    static func isFailureStatus(_ normalizedStatus: String) -> Bool {
        failureStatuses.contains(normalizedStatus)
    }

    static func knowsTool(_ rawTool: String) -> Bool {
        let normalizedTool = normalizeTool(rawTool)
        return supportedTools.contains(normalizedTool)
            || legacyRemovedTools.contains(normalizedTool)
    }

    static func events(
        rawTool: String,
        arguments: [String: Any],
        metadata: [String: String],
        status: String?,
        failureDetail: String?
    ) -> [IDEStateSyntheticEvent] {
        let normalizedTool = normalizeTool(rawTool)
        guard knowsTool(normalizedTool) else { return [] }

        let normalizedStatus = (status ?? metadata["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        func wrapped(_ type: String, _ payload: [String: String]) -> IDEStateSyntheticEvent {
            IDEStateSyntheticEvent(type: type, payload: merge(payload, metadata: metadata))
        }

        func failureEvent(
            toolName: String,
            detail: String,
            errorCode: String = "mcp_tool_call_failed"
        ) -> IDEStateSyntheticEvent {
            wrapped("tool_validation_error", [
                "title": "\(toolName) failed",
                "detail": detail,
                "status": "failed",
                "error_code": errorCode,
                "tool": toolName,
            ])
        }

        if legacyRemovedTools.contains(normalizedTool) {
            return [wrapped("tool_validation_error", [
                "title": "Legacy debug_panel is not supported",
                "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                "status": "failed",
                "error_code": "legacy_debug_panel_removed",
                "tool": normalizedTool,
            ])]
        }

        if normalizedTool == "todo_write", arguments.keys.contains("todos") {
            guard let parsedTodos = parseTodoArrayArgument(arguments["todos"]) else {
                return [failureEvent(
                    toolName: normalizedTool,
                    detail: "'todos' must be a valid JSON array",
                    errorCode: "invalid_todos_payload"
                )]
            }
            if isFailureStatus(normalizedStatus) {
                let detail = failureDetail ?? "MCP tool call failed"
                return [failureEvent(toolName: normalizedTool, detail: detail)]
            }
            if parsedTodos.isEmpty {
                return [wrapped("todo_write", [
                    "todos_json": "[]",
                    "title": "__CODERIDE_CLEAR_TODOS__",
                    "clear_todos": "true",
                ])]
            }
            if let todosData = try? JSONSerialization.data(withJSONObject: parsedTodos, options: [.sortedKeys]),
               let todosJSON = String(data: todosData, encoding: .utf8) {
                return [wrapped("todo_write", [
                    "todos_json": todosJSON,
                    "title": "Todo updated",
                ])]
            }
            return []
        }

        if isFailureStatus(normalizedStatus) {
            return [failureEvent(
                toolName: normalizedTool,
                detail: failureDetail ?? "MCP tool call failed"
            )]
        }

        switch normalizedTool {
        case "todo_write":
            var payload: [String: String] = [:]
            if let title = firstNonEmptyString(in: arguments, keys: ["title", "content"]) {
                payload["title"] = title
            }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) {
                payload["status"] = status
            }
            if let priority = firstNonEmptyString(in: arguments, keys: ["priority"]) {
                payload["priority"] = priority
            }
            if let notes = firstNonEmptyString(in: arguments, keys: ["notes"]) {
                payload["notes"] = notes
            }
            if let activeForm = firstNonEmptyString(in: arguments, keys: ["activeForm", "active_form"]) {
                payload["activeForm"] = activeForm
            }
            if let files = jsonStringArgument(in: arguments, keys: ["linkedFiles", "linked_files", "files"]) {
                payload["files"] = files
            }
            return payload.isEmpty ? [] : [wrapped("todo_write", payload)]

        case "todo_read":
            return [wrapped("todo_read", [:])]

        case "plan_step_update", "plan_step":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) { payload["status"] = status }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            return payload.isEmpty ? [] : [wrapped("plan_step_update", payload)]

        case "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff", "plan_request_user_input":
            guard let mapped = mapPlanLifecycleEvent(tool: normalizedTool, arguments: arguments) else {
                return []
            }
            return [wrapped(mapped.type, mapped.payload)]

        case "debug_set_phase":
            var payload: [String: String] = [:]
            if let phase = firstNonEmptyString(in: arguments, keys: ["phase"]) { payload["phase"] = phase }
            if let detail = firstNonEmptyString(in: arguments, keys: ["detail"]) { payload["detail"] = detail }
            return payload["phase"] != nil ? [wrapped("debug_phase_update", payload)] : []

        case "debug_request_user":
            var payload: [String: String] = [:]
            if let kind = firstNonEmptyString(in: arguments, keys: ["kind"]) { payload["kind"] = kind }
            if let prompt = firstNonEmptyString(in: arguments, keys: ["prompt"]) { payload["prompt"] = prompt }
            return (payload["kind"] != nil && payload["prompt"] != nil)
                ? [wrapped("debug_user_request", payload)]
                : []

        case "debug_resolve":
            if let summary = firstNonEmptyString(in: arguments, keys: ["summary", "detail", "message"]) {
                return [wrapped("debug_resolved", ["summary": summary])]
            }
            return []

        case "policy_ack":
            if let hash = firstNonEmptyString(in: arguments, keys: ["hash"]) {
                return [wrapped("policy_ack", ["hash": hash])]
            }
            return []

        case "mermaid_render":
            var payload: [String: String] = [:]
            if let code = firstNonEmptyString(in: arguments, keys: ["code"]) { payload["code"] = code }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            return payload["code"] != nil ? [wrapped("mermaid_render", payload)] : []

        case "activate_plan_mode", "activate_debug_mode":
            if let reason = firstNonEmptyString(in: arguments, keys: ["reason"]) {
                return [wrapped(normalizedTool, ["reason": reason])]
            }
            return [wrapped(normalizedTool, [:])]

        case "show_task_panel":
            return [wrapped("coderide_show_task_panel", [:])]

        case "show_swarm_panel":
            if let swarmID = firstNonEmptyString(in: arguments, keys: ["swarm_id"]) {
                return [wrapped("coderide_show_swarm_panel", ["swarm_id": swarmID])]
            }
            return [wrapped("coderide_show_swarm_panel", [:])]

        default:
            return []
        }
    }

    private static func merge(
        _ payload: [String: String],
        metadata: [String: String]
    ) -> [String: String] {
        var merged = metadata
        for (key, value) in payload where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    private static func firstNonEmptyString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    private static func parseTodoArrayArgument(_ raw: Any?) -> [[String: Any]]? {
        if let array = raw as? [[String: Any]] {
            return array
        }
        if let rawString = raw as? String {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
                return []
            }
            return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        }
        return nil
    }

    private static func jsonStringArgument(
        in arguments: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = arguments[key] else { continue }
            if let raw = value as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                continue
            }
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8),
                  !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return json
        }
        return nil
    }

    private static func mapPlanLifecycleEvent(
        tool: String,
        arguments: [String: Any]
    ) -> (type: String, payload: [String: String])? {
        switch tool {
        case "plan_create":
            var payload: [String: String] = [:]
            if let goal = firstNonEmptyString(in: arguments, keys: ["goal"]) { payload["goal"] = goal }
            if let chosenPath = firstNonEmptyString(in: arguments, keys: ["chosen_path", "chosenPath"]) { payload["chosen_path"] = chosenPath }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let steps = jsonStringArgument(in: arguments, keys: ["steps"]) { payload["steps"] = steps }
            return payload.isEmpty ? nil : ("plan_create", payload)

        case "plan_read":
            var payload: [String: String] = [:]
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let includeHistory = firstNonEmptyString(in: arguments, keys: ["include_history", "includeHistory"]) { payload["include_history"] = includeHistory }
            if let historyLimit = firstNonEmptyString(in: arguments, keys: ["history_limit", "historyLimit"]) { payload["history_limit"] = historyLimit }
            return ("plan_read", payload)

        case "plan_step_upsert":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) { payload["status"] = status }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let description = firstNonEmptyString(in: arguments, keys: ["description"]) { payload["description"] = description }
            if let targetFile = firstNonEmptyString(in: arguments, keys: ["target_file", "targetFile"]) { payload["target_file"] = targetFile }
            if let notes = firstNonEmptyString(in: arguments, keys: ["notes"]) { payload["notes"] = notes }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            if let linkedFiles = jsonStringArgument(in: arguments, keys: ["linked_files", "linkedFiles"]) { payload["linked_files"] = linkedFiles }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            return payload.isEmpty ? nil : ("plan_step_upsert", payload)

        case "plan_step_batch_update":
            var payload: [String: String] = [:]
            if let updates = jsonStringArgument(in: arguments, keys: ["updates"]) { payload["updates"] = updates }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_batch_update", payload)

        case "plan_step_reorder":
            var payload: [String: String] = [:]
            if let ordered = jsonStringArgument(in: arguments, keys: ["ordered_step_ids", "orderedStepIds"]) { payload["ordered_step_ids"] = ordered }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_reorder", payload)

        case "plan_step_dependency_set":
            var payload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) { payload["step_id"] = stepID }
            if let dependsOn = jsonStringArgument(in: arguments, keys: ["depends_on", "dependsOn"]) { payload["depends_on"] = dependsOn }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_step_dependency_set", payload)

        case "plan_set_walkthrough":
            var payload: [String: String] = [:]
            if let markdown = firstNonEmptyString(in: arguments, keys: ["markdown"]) { payload["markdown"] = markdown }
            if let summary = firstNonEmptyString(in: arguments, keys: ["summary"]) { payload["summary"] = summary }
            if let outcome = firstNonEmptyString(in: arguments, keys: ["outcome"]) { payload["outcome"] = outcome }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_set_walkthrough", payload)

        case "plan_history_read":
            var payload: [String: String] = [:]
            if let limit = firstNonEmptyString(in: arguments, keys: ["limit"]) { payload["limit"] = limit }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return ("plan_history_read", payload)

        case "plan_diff":
            var payload: [String: String] = [:]
            if let fromSnapshotID = firstNonEmptyString(in: arguments, keys: ["from_snapshot_id", "fromSnapshotId"]) { payload["from_snapshot_id"] = fromSnapshotID }
            if let toSnapshotID = firstNonEmptyString(in: arguments, keys: ["to_snapshot_id", "toSnapshotId"]) { payload["to_snapshot_id"] = toSnapshotID }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_diff", payload)

        case "plan_request_user_input":
            var payload: [String: String] = [:]
            if let questions = jsonStringArgument(in: arguments, keys: ["questions"]) { payload["questions"] = questions }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) { payload["title"] = title }
            if let phase = firstNonEmptyString(in: arguments, keys: ["phase"]) { payload["phase"] = phase }
            if let round = firstNonEmptyString(in: arguments, keys: ["round"]) { payload["round"] = round }
            if let context = firstNonEmptyString(in: arguments, keys: ["context"]) { payload["context"] = context }
            if let conversationID = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) { payload["conversation_id"] = conversationID }
            return payload.isEmpty ? nil : ("plan_request_user_input", payload)

        default:
            return nil
        }
    }
}
