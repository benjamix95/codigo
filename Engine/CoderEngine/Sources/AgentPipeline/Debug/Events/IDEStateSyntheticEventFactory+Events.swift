import Foundation

// MARK: - IDEStateSyntheticEventFactory + Events

extension IDEStateSyntheticEventFactory {

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
            errorCode: String? = nil
        ) -> IDEStateSyntheticEvent {
            wrapped("tool_validation_error", [
                "title": "\(toolName) failed",
                "detail": detail,
                "status": "failed",
                "error_code": errorCode ?? metadata["error_code"] ?? "mcp_tool_call_failed",
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
            guard let mapped = Self.mapPlanLifecycleEvent(tool: normalizedTool, arguments: arguments) else {
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

        case "review_start":
            var payload: [String: String] = [:]
            for key in [
                "scope", "ref", "max_workers", "max_rounds",
                "analysis_backend", "execution_backend",
                "session_id", "conversation_id",
            ] {
                if let value = firstNonEmptyString(in: arguments, keys: [key]) {
                    payload[key] = value
                }
            }
            return [wrapped("review_start", payload)]

        case "review_list_sessions", "review_status", "review_findings",
             "review_get_outcome", "security_status", "security_findings",
             "bughunter_status", "bughunter_findings",
             "bughunter_run_history", "bughunter_explain_cluster":
            var payload: [String: String] = [:]
            for key in [
                "session_id", "conversation_id", "kind", "severity",
                "origin", "category", "file", "status", "limit",
            ] {
                if let value = firstNonEmptyString(in: arguments, keys: [key]) {
                    payload[key] = value
                }
            }
            return [wrapped(normalizedTool, payload)]

        case "review_apply_fix":
            var payload: [String: String] = [:]
            if let findingId = firstNonEmptyString(in: arguments, keys: ["finding_id"]) {
                payload["finding_id"] = findingId
            }
            if let sessionId = firstNonEmptyString(in: arguments, keys: ["session_id"]) {
                payload["session_id"] = sessionId
            }
            if let conversationId = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) {
                payload["conversation_id"] = conversationId
            }
            return payload.isEmpty ? [] : [wrapped("review_apply_fix", payload)]

        case "review_dismiss":
            var payload: [String: String] = [:]
            if let findingId = firstNonEmptyString(in: arguments, keys: ["finding_id"]) {
                payload["finding_id"] = findingId
            }
            if let reason = firstNonEmptyString(in: arguments, keys: ["reason"]) {
                payload["reason"] = reason
            }
            if let sessionId = firstNonEmptyString(in: arguments, keys: ["session_id"]) {
                payload["session_id"] = sessionId
            }
            if let conversationId = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) {
                payload["conversation_id"] = conversationId
            }
            return payload.isEmpty ? [] : [wrapped("review_dismiss", payload)]

        case "review_comment":
            var payload: [String: String] = [:]
            if let findingId = firstNonEmptyString(in: arguments, keys: ["finding_id"]) {
                payload["finding_id"] = findingId
            }
            if let content = firstNonEmptyString(in: arguments, keys: ["content"]) {
                payload["content"] = content
            }
            if let author = firstNonEmptyString(in: arguments, keys: ["author"]) {
                payload["author"] = author
            }
            if let sessionId = firstNonEmptyString(in: arguments, keys: ["session_id"]) {
                payload["session_id"] = sessionId
            }
            if let conversationId = firstNonEmptyString(in: arguments, keys: ["conversation_id", "conversationId"]) {
                payload["conversation_id"] = conversationId
            }
            return payload.isEmpty ? [] : [wrapped("review_comment", payload)]

        case "review_configure":
            var payload: [String: String] = [:]
            for key in [
                "session_id", "conversation_id", "max_workers", "max_rounds",
                "analysis_backend", "execution_backend",
            ] {
                if let value = firstNonEmptyString(in: arguments, keys: [key]) {
                    payload[key] = value
                }
            }
            return payload.isEmpty ? [] : [wrapped("review_configure", payload)]

        default:
            return []
        }
    }
}
