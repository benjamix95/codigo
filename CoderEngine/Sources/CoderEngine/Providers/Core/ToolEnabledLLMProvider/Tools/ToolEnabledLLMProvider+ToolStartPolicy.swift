import Foundation

extension ToolEnabledLLMProvider {
    // MARK: - Parallel Tool Execution

    /// Tools that only read data and can safely run concurrently
    private static let readOnlyToolNames: Set<String> = [
        "read", "glob", "grep", "codebase_search", "find_symbol", "list_symbols",
        "find_references", "project_structure", "file_outline", "find_files",
        "codebase_stats", "dependency_graph", "list_types", "list_tests",
        "index_status", "read_range", "list_dir", "git_diff", "read_json",
        "workspace_stats", "tail_log", "list_processes", "search_symbols",
        "mcp_list_tools", "mcp_describe_tool", "mcp_list_servers", "mcp_health",
        "mcp_list_resources", "mcp_read_resource", "mcp_list_prompts", "mcp_get_prompt",
        "debug_query", "semantic_search", "related_files", "git_log_search",
        "read_lints", "debug_context",
        "batch_read", "diff_files", "git_status", "git_show", "code_context",
        "web_search", "web_fetch",
        "subagent_explorer",
    ]

    // MARK: - Real-time tool start events

    /// Maps a tool name to the event type used for its "started" trace event.
    /// These types must pass ToolTraceVisibility and have isRunning == true.
    static func toolStartEventType(for toolName: String) -> String {
        switch toolName {
        case "bash":
            return "command_execution"
        case "edit", "write", "str_replace", "create_file", "delete_file", "parallel_apply", "regex_replace",
             "apply_patch", "multi_edit", "multiedit",
             "rename_symbol", "find_and_replace_all", "undo_edit":
            return "file_change"
        case "web_search":
            return "web_search_started"
        case "web_fetch":
            return "web_fetch_started"
        case _ where toolName.hasPrefix("subagent_"):
            return "agent"
        case "skill":
            return "skill_invocation"
        default:
            return "read_batch_started"
        }
    }

    static func toolWouldMutate(toolName: String, args: [String: String]) -> Bool {
        !isReadOnlyTool(toolName: toolName, args: args)
    }

    static func isReadOnlyTool(toolName: String, args: [String: String]) -> Bool {
        let normalized = ProviderToolEventMapper.normalizeToolIdentifier(toolName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        if readOnlyToolNames.contains(normalized) {
            return true
        }

        if normalized == "mcp_logs" {
            let action = (args["action"] ?? "read")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return action == "read"
        }

        if normalized == "mcp_call" {
            let targetTool = ProviderToolEventMapper.normalizeToolIdentifier(
                args["tool"] ?? args["mcp_tool"] ?? args["tool_name"] ?? ""
            )
            if targetTool.isEmpty || targetTool == normalized {
                return false
            }
            return isReadOnlyTool(toolName: targetTool, args: args)
        }

        if normalized.hasPrefix("mcp_") {
            return false
        }

        if let role = SubagentRole.fromToolName(normalized) {
            return !role.canEditFiles
        }

        if MCPNativeToolRegistry.shared.routing[normalized] != nil {
            return isLikelyReadOnlyNativeMCPTool(normalized)
        }

        return false
    }

    static func isLikelyReadOnlyNativeMCPTool(_ toolName: String) -> Bool {
        let normalized = toolName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let mutatingSignals = [
            "write", "edit", "create", "delete", "remove", "replace", "rename",
            "apply", "patch", "run", "build", "test", "push", "commit", "restart",
            "set_", "clear", "terminate", "kill", "pause", "resume",
        ]
        if mutatingSignals.contains(where: { normalized.contains($0) }) {
            return false
        }

        let readSignals = [
            "read", "list", "get", "describe", "search", "find", "grep", "glob",
            "outline", "status", "health", "query", "stats", "context",
        ]
        return readSignals.contains(where: { normalized.contains($0) })
    }

    /// Builds a payload for the real-time "started" event emitted before tool execution.
    static func toolStartPayload(for toolName: String, args: [String: String]) -> [String: String] {
        var payload: [String: String] = [
            "tool": toolName,
            "name": toolName,
            "status": "started",
            "tool_call_id": args["id"] ?? "",
        ]
        if let command = args["command"], !command.isEmpty {
            payload["command"] = command
            payload["title"] = "Bash"
            payload["detail"] = command
        }
        if let path = args["path"], !path.isEmpty { payload["path"] = path }
        if let query = args["query"], !query.isEmpty { payload["query"] = query }
        if let url = args["url"], !url.isEmpty { payload["url"] = url }
        if let server = args["server"] ?? args["server_id"], !server.isEmpty {
            payload["server_id"] = server
            payload["mcp_server"] = server
        }
        if let swarmId = args["swarm_id"], !swarmId.isEmpty {
            payload["swarm_id"] = swarmId
            payload["group_id"] = "swarm-\(swarmId)"
        }
        if toolName == "skill", let skillName = args["skill"] ?? args["name"], !skillName.isEmpty {
            payload["skill"] = skillName
        }
        if payload["title"] == nil {
            payload["title"] = toolStartTitle(for: toolName, args: args)
        }
        return payload
    }

    static func toolStartTitle(for toolName: String, args: [String: String]) -> String {
        let pathComponent = { (key: String) -> String in
            ((args[key] ?? "") as NSString).lastPathComponent
        }
        switch toolName {
        case "bash":
            return "Bash"
        case "edit", "str_replace":
            let file = pathComponent("path")
            return file.isEmpty ? "Edit" : "Edit • \(file)"
        case "write", "create_file":
            let file = pathComponent("path")
            return file.isEmpty ? "Write" : "Write • \(file)"
        case "read", "read_range":
            let file = pathComponent("path")
            return file.isEmpty ? "Read" : "Read • \(file)"
        case "glob":
            let pattern = args["pattern"] ?? ""
            return pattern.isEmpty ? "Glob" : "Glob • \(pattern)"
        case "grep":
            let query = args["query"] ?? ""
            return query.isEmpty ? "Grep" : "Grep • \(query)"
        case "semantic_search":
            return "Semantic search"
        case "codebase_search":
            return "Codebase search"
        case "find_symbol":
            return "Find symbol"
        case "find_references":
            return "Find references"
        case "web_search":
            return "Web search"
        case "web_fetch":
            return "Fetching web page"
        case "diagnostics":
            return "Diagnostics"
        case "build_project":
            return "Building project"
        case "run_tests", "run_single_test":
            return "Running tests"
        case "skill":
            let name = args["skill"] ?? args["name"] ?? ""
            return name.isEmpty ? "Skill" : "Skill • \(name)"
        default:
            if toolName.hasPrefix("subagent_") {
                let role = SubagentRole.fromToolName(toolName)
                return role.map { "\($0.displayName) subagent" } ?? toolName
            }
            return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: - Inline Subagent Execution

    /// Execute a subagent tool inline during the agent's streaming loop.

}
