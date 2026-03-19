import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static let mcpEditRuntimeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace", "create_file",
    ]

    static let ideStateTools: Set<String> = Set([
        "todo_write", "todo_read", "plan_step_update", "mermaid_render",
        "debug_set_phase", "debug_request_user", "debug_resolve",
        "policy_ack", "activate_plan_mode", "activate_debug_mode",
        "show_task_panel", "show_swarm_panel",
        "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_history_read", "plan_diff", "plan_request_user_input",
    ]).union(Set(SubagentRole.allToolNames))

    /// IDE state tools are pass-through. The MCP server acknowledges the call
    /// and returns a confirmation. The actual state update happens when the host
    /// process (CoderIDE) sees the MCP tool call event in the Codex CLI stream
    /// and routes it through EventNormalizer → TodoStore / ChatStore.
    static func handleIDEStateTool(
        name: String,
        args: [String: String],
        richArgs: [String: Any] = [:]
    ) -> CallTool.Result {
        if let planResult = handlePlanIDEStateTool(name: name, args: args) {
            return planResult
        }
        switch name {
        case "todo_write":
            let todosRaw = (args["todos"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let titleRaw = (args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let validStatuses: Set<String> = [
                "pending", "in_progress", "done", "blocked",
                // Common LLM aliases
                "completed", "complete", "finished",
                "running", "active", "doing", "started",
                "todo", "open", "queued", "waiting",
                "failed", "error", "stuck",
                "cancelled", "canceled", "aborted", "skipped",
            ]

            if richArgs["todos"] != nil || !todosRaw.isEmpty {
                guard let parsedTodos = IDEStateTodoArgumentParser.parse(richArgs["todos"] ?? todosRaw) else {
                    return CallTool.Result(
                        content: [.text("Error: 'todos' must be a valid todo collection. Use a JSON array, a single JSON object, or a checklist string.")],
                        isError: true
                    )
                }
                guard !parsedTodos.isEmpty else {
                    return CallTool.Result(
                        content: [.text("OK — empty todo list received, clear request acknowledged")],
                        isError: nil
                    )
                }
                for (i, item) in parsedTodos.enumerated() {
                    let content = (item["content"] as? String ?? item["title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if content.isEmpty {
                        return CallTool.Result(
                            content: [.text("Error: item \(i) missing 'content' or 'title'")],
                            isError: true
                        )
                    }
                    if let itemStatus = (item["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                       !itemStatus.isEmpty,
                       !validStatuses.contains(itemStatus) {
                        return CallTool.Result(
                            content: [.text("Error: item \(i) has invalid status '\(itemStatus)'. Use: pending, in_progress, done, blocked")],
                            isError: true
                        )
                    }
                }
            } else if titleRaw.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: provide either 'todos' (JSON array) or 'title' parameter")],
                    isError: true
                )
            }

            // Validate status value if provided (single-item shorthand)
            if let status = args["status"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !status.isEmpty,
               !validStatuses.contains(status) {
                return CallTool.Result(
                    content: [.text("Error: invalid status '\(status)'. Use: pending, in_progress, done, blocked")],
                    isError: true
                )
            }
            var rustArgs = args
            if richArgs["todos"] != nil || !todosRaw.isEmpty {
                guard let parsedTodos = IDEStateTodoArgumentParser.parse(richArgs["todos"] ?? todosRaw) else {
                    return CallTool.Result(
                        content: [.text("Error: 'todos' must be a valid todo collection. Use a JSON array, a single JSON object, or a checklist string.")],
                        isError: true
                    )
                }
                rustArgs["todos"] = encodeJSONAny(parsedTodos) ?? "[]"
            }
            return handleTodoToolWithRust(action: "todo_write", arguments: rustArgs)

        case "todo_read":
            return handleTodoToolWithRust(action: "todo_read", arguments: args)

        case "plan_step_update":
            let stepId = (args["step_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (args["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stepId.isEmpty || status.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'step_id' and 'status' are required")],
                    isError: true
                )
            }
            if !["pending", "running", "done", "failed"].contains(status.lowercased()) {
                return CallTool.Result(
                    content: [.text("Error: invalid status '\(status)'. Use: pending, running, done, failed")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — plan step \(stepId) updated to \(status)")], isError: nil)

        case "mermaid_render":
            let code = (args["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'code' parameter is required and must contain valid mermaid syntax")],
                    isError: true
                )
            }
            let title = args["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleInfo = title.map { " (\($0))" } ?? ""
            return CallTool.Result(content: [.text("OK — mermaid diagram rendered in IDE\(titleInfo)")], isError: nil)

        case "debug_set_phase":
            let phase = (args["phase"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validPhases: Set<String> = [
                "describing", "reproducing", "fixing", "instrumenting", "verifying", "resolved"
            ]
            if phase.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'phase' parameter is required")],
                    isError: true
                )
            }
            if !validPhases.contains(phase) {
                return CallTool.Result(
                    content: [.text("Error: invalid phase '\(phase)'. Use: describing, reproducing, fixing, instrumenting, verifying, resolved")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug phase set to \(phase)")], isError: nil)

        case "debug_request_user":
            let kind = (args["kind"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let prompt = (args["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let validKinds: Set<String> = ["question", "reproduce"]
            if kind.isEmpty || prompt.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'kind' and 'prompt' parameters are required")],
                    isError: true
                )
            }
            if !validKinds.contains(kind) {
                return CallTool.Result(
                    content: [.text("Error: invalid kind '\(kind)'. Use: question, reproduce")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug user request '\(kind)' queued")], isError: nil)

        case "debug_resolve":
            let summary = (args["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'summary' parameter is required")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug session resolved")], isError: nil)

        case "policy_ack":
            let hash = (args["hash"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if hash.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'hash' parameter is required")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — policy acknowledged")], isError: nil)

        case "activate_plan_mode":
            return CallTool.Result(content: [.text("OK — plan mode activated")], isError: nil)

        case "activate_debug_mode":
            return CallTool.Result(content: [.text("OK — debug mode activated")], isError: nil)

        case "show_task_panel":
            return CallTool.Result(content: [.text("OK — task panel shown")], isError: nil)

        case "show_swarm_panel":
            return CallTool.Result(content: [.text("OK — swarm panel opened")], isError: nil)

        case let toolName where SubagentRole.fromToolName(toolName) != nil:
            let task = (args["task"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty, let role = SubagentRole.fromToolName(toolName) else {
                return CallTool.Result(
                    content: [.text("Error: 'task' parameter is required")],
                    isError: true
                )
            }
            return CallTool.Result(
                content: [.text("OK — subagent \(role.displayName) launched")],
                isError: nil
            )

        default:
            return CallTool.Result(content: [.text("Unknown IDE state tool: \(name)")], isError: true)
        }
    }
}

private extension CoderIDEMCPServerApp {
    static func handleTodoToolWithRust(
        action: String,
        arguments: [String: String]
    ) -> CallTool.Result {
        let response: TodoStateRustResponse? = ReviewCoreBridge.call(
            functionName: "todo_state_handle_action",
            request: TodoStateRustRequest(
                schemaVersion: 1,
                action: action,
                arguments: arguments
            )
        )

        guard let response else {
            return CallTool.Result(
                content: [.text("Error: Rust todo state core unavailable for \(action)")],
                isError: true
            )
        }
        if let error = response.error {
            return CallTool.Result(content: [.text(error.message)], isError: true)
        }
        return CallTool.Result(content: [.text(response.message ?? "OK")], isError: nil)
    }
}

private struct TodoStateRustRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let arguments: [String: String]
}

private struct TodoStateRustResponse: Decodable {
    let schemaVersion: Int
    let error: TodoStateRustError?
    let message: String?
}

private struct TodoStateRustError: Decodable {
    let code: String
    let message: String
}
