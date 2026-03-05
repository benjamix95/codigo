import Foundation
import CoderEngine
import MCP

extension CoderIDEMCPServerApp {
    static let mcpEditRuntimeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace", "create_file",
    ]

    static let ideStateTools: Set<String> = [
        "todo_write", "todo_read", "plan_step_update", "mermaid_render",
        "debug_set_phase", "debug_request_user", "debug_resolve",
        "policy_ack", "activate_plan_mode", "activate_debug_mode",
        "show_task_panel", "show_swarm_panel",
        "plan_create", "plan_read", "plan_step_upsert", "plan_step_batch_update",
        "plan_step_reorder", "plan_step_dependency_set", "plan_set_walkthrough",
        "plan_history_read", "plan_diff", "plan_request_user_input",
        // Code review tools
        "review_start", "review_status", "review_findings",
        "review_apply_fix", "review_dismiss", "review_configure",
        "review_diff_summary", "review_comment",
    ]

    /// IDE state tools are pass-through. The MCP server acknowledges the call
    /// and returns a confirmation. The actual state update happens when the host
    /// process (CoderIDE) sees the MCP tool call event in the Codex CLI stream
    /// and routes it through EventNormalizer → TodoStore / ChatStore.
    static func handleIDEStateTool(name: String, args: [String: String]) -> CallTool.Result {
        if let planResult = handlePlanIDEStateTool(name: name, args: args) {
            return planResult
        }
        if let reviewResult = handleCodeReviewTool(name: name, args: args) {
            return reviewResult
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
            ]

            if !todosRaw.isEmpty {
                // Validate JSON structure
                guard let data = todosRaw.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) else {
                    return CallTool.Result(
                        content: [.text("Error: 'todos' is not valid JSON. Expected a JSON array of objects, e.g. [{\"content\":\"Task\",\"status\":\"pending\"}]")],
                        isError: true
                    )
                }
                guard let array = parsed as? [[String: Any]], !array.isEmpty else {
                    if parsed is [Any] {
                        // Empty array — treated as an explicit clear request by IDE event handlers.
                        return CallTool.Result(content: [.text("OK — empty todo list received, clear request acknowledged")], isError: nil)
                    }
                    return CallTool.Result(
                        content: [.text("Error: 'todos' must be a JSON array of objects, not \(type(of: parsed))")],
                        isError: true
                    )
                }
                for (i, item) in array.enumerated() {
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
            return CallTool.Result(content: [.text("OK — todo list updated")], isError: nil)

        case "todo_read":
            // Read from the shared state file written by the main IDE app.
            let todos = MCPSharedState.readTodos()
            if todos.isEmpty {
                return CallTool.Result(content: [.text("No todos found.")], isError: nil)
            }
            var lines: [String] = []
            var doneCount = 0
            for todo in todos {
                let title = (todo["title"] as? String) ?? "(untitled)"
                let status = (todo["status"] as? String) ?? "pending"
                let priority = (todo["priority"] as? String) ?? "medium"
                let activeForm = (todo["activeForm"] as? String) ?? ""
                let icon: String
                switch status {
                case "done":
                    icon = "[x]"
                    doneCount += 1
                case "in_progress": icon = "[~]"
                case "blocked": icon = "[!]"
                default: icon = "[ ]"
                }
                let formSuffix = status == "in_progress" && !activeForm.isEmpty ? " — \(activeForm)" : ""
                let linkedFiles = (todo["linkedFiles"] as? [String]) ?? []
                let filesSuffix = linkedFiles.isEmpty ? "" : " [files: \(linkedFiles.joined(separator: ", "))]"
                lines.append("\(icon) \(title)\(formSuffix) (\(priority))\(filesSuffix)")
            }
            lines.append("--- \(todos.count) total, \(doneCount) done ---")
            return CallTool.Result(content: [.text(lines.joined(separator: "\n"))], isError: nil)

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

        default:
            return CallTool.Result(content: [.text("Unknown IDE state tool: \(name)")], isError: true)
        }
    }
}
