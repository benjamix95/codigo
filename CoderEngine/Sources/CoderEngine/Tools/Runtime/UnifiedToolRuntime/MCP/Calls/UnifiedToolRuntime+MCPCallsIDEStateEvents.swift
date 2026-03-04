import Foundation

extension UnifiedToolRuntime {
    static func syntheticIDEStateEventsFromMCP(
        call: ToolCall,
        completedPayload: [String: String]
    ) -> [StreamEvent] {
        let rawTool = firstNonEmptyString(
            in: completedPayload,
            keys: ["mcp_tool", "tool_name"]
        ) ?? firstNonEmptyString(
            in: call.args,
            keys: ["mcp_tool", "tool", "name"]
        ) ?? ""
        let normalizedTool = normalizeIDEStateMCPTool(rawTool)
        guard ideStateMCPTools.contains(normalizedTool) else {
            return []
        }

        let arguments = mergedMCPCallArguments(from: call.args)
        let metadata = syntheticMCPMetadata(
            call: call,
            completedPayload: completedPayload,
            arguments: arguments,
            normalizedTool: normalizedTool
        )
        let normalizedStatus = (metadata["status"] ?? completedPayload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        func wrapped(_ type: String, _ payload: [String: String]) -> StreamEvent {
            .raw(type: type, payload: mergeSyntheticPayload(payload, metadata: metadata))
        }

        func failedToolCallEvent(for toolName: String) -> [StreamEvent] {
            let detail = firstNonEmptyString(
                in: completedPayload,
                keys: ["detail", "error", "stderr", "output"]
            ) ?? "MCP tool call failed"
            return [wrapped("tool_validation_error", [
                "title": "\(toolName) failed",
                "detail": detail,
                "status": "failed",
                "error_code": "mcp_tool_call_failed",
                "tool": toolName,
            ])]
        }

        if isFailureMCPToolStatus(normalizedStatus) {
            return failedToolCallEvent(for: normalizedTool)
        }

        switch normalizedTool {
        case "todo_write":
            var todoPayload: [String: String] = [:]
            if arguments.keys.contains("todos") {
                guard let parsedTodos = parseTodoArrayArgument(arguments["todos"]) else {
                    return [wrapped("tool_validation_error", [
                        "title": "Invalid todo payload",
                        "detail": "'todos' must be a valid JSON array",
                        "status": "failed",
                        "error_code": "invalid_todos_payload",
                        "tool": normalizedTool,
                    ])]
                }
                if parsedTodos.isEmpty {
                    return []
                }
                if let todosData = try? JSONSerialization.data(withJSONObject: parsedTodos, options: [.sortedKeys]),
                   let todosJSON = String(data: todosData, encoding: .utf8) {
                    todoPayload["todos_json"] = todosJSON
                    todoPayload["title"] = "Todo updated"
                }
            } else {
                if let title = firstNonEmptyString(in: arguments, keys: ["title", "content"]) {
                    todoPayload["title"] = title
                }
                if let status = firstNonEmptyString(in: arguments, keys: ["status"]) {
                    todoPayload["status"] = status
                }
                if let priority = firstNonEmptyString(in: arguments, keys: ["priority"]) {
                    todoPayload["priority"] = priority
                }
                if let notes = firstNonEmptyString(in: arguments, keys: ["notes"]) {
                    todoPayload["notes"] = notes
                }
                if let activeForm = firstNonEmptyString(in: arguments, keys: ["activeForm", "active_form"]) {
                    todoPayload["activeForm"] = activeForm
                }
            }
            if todoPayload.isEmpty {
                return []
            }
            return [wrapped("todo_write", todoPayload)]

        case "todo_read":
            return [wrapped("todo_read", [:])]

        case "plan_step_update", "plan_step":
            var planPayload: [String: String] = [:]
            if let stepID = firstNonEmptyString(in: arguments, keys: ["step_id", "stepId"]) {
                planPayload["step_id"] = stepID
            }
            if let status = firstNonEmptyString(in: arguments, keys: ["status"]) {
                planPayload["status"] = status
            }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) {
                planPayload["title"] = title
            }
            if planPayload.isEmpty {
                return []
            }
            return [wrapped("plan_step_update", planPayload)]

        case "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
             "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
             "plan_history_read", "plan_diff", "plan_request_user_input":
            let mapped = mapPlanLifecycleMCPEvent(tool: normalizedTool, arguments: arguments)
            guard let mapped else { return [] }
            return [wrapped(mapped.type, mapped.payload)]

        case "debug_set_phase":
            var payload: [String: String] = [:]
            if let phase = firstNonEmptyString(in: arguments, keys: ["phase"]) {
                payload["phase"] = phase
            }
            if let detail = firstNonEmptyString(in: arguments, keys: ["detail"]) {
                payload["detail"] = detail
            }
            return payload["phase"] != nil ? [wrapped("debug_phase_update", payload)] : []

        case "debug_request_user":
            var payload: [String: String] = [:]
            if let kind = firstNonEmptyString(in: arguments, keys: ["kind"]) {
                payload["kind"] = kind
            }
            if let prompt = firstNonEmptyString(in: arguments, keys: ["prompt"]) {
                payload["prompt"] = prompt
            }
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
            if let code = firstNonEmptyString(in: arguments, keys: ["code"]) {
                payload["code"] = code
            }
            if let title = firstNonEmptyString(in: arguments, keys: ["title"]) {
                payload["title"] = title
            }
            return payload["code"] != nil ? [wrapped("mermaid_render", payload)] : []

        case "activate_plan_mode":
            if let reason = firstNonEmptyString(in: arguments, keys: ["reason"]) {
                return [wrapped("activate_plan_mode", ["reason": reason])]
            }
            return [wrapped("activate_plan_mode", [:])]

        case "activate_debug_mode":
            if let reason = firstNonEmptyString(in: arguments, keys: ["reason"]) {
                return [wrapped("activate_debug_mode", ["reason": reason])]
            }
            return [wrapped("activate_debug_mode", [:])]

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
}
