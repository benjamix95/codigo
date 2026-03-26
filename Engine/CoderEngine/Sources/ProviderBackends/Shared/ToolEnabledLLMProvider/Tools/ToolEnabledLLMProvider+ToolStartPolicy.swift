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
        "plan_read", "plan_history_read", "plan_diff",
        "subagent_explorer", "subagent_reviewer", "subagent_bugHunter", "subagent_securityAuditor",
    ]

    // MARK: - Real-time tool start events

    /// Maps a tool name to the event type used for its "started" trace event.
    /// These types must pass ToolTraceVisibility and have isRunning == true.
    static func toolStartEventType(for toolName: String) -> String {
        if resolveSubagentInvocation(toolName: toolName, payload: [:]) != nil {
            return "agent"
        }
        switch toolName {
        case "bash":
            return "command_execution"
        case "semantic_search":
            return "semantic_search"
        case "grep", "glob", "codebase_search", "find_symbol", "find_references",
             "find_files", "search_symbols", "search_health_check":
            return "search"
        case "read", "read_range", "batch_read":
            return "read_batch_started"
        case "read_lints":
            return "read_lints"
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
            payload["title"] = AgentToolUIDisplayName.label(forRuntimeTool: "bash")
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
        if let resolvedSubagent = resolveSubagentInvocation(toolName: toolName, payload: args) {
            let identity = SubagentExecutionIdentityBuilder.make(
                role: resolvedSubagent.role,
                task: args["task"] ?? args["prompt"] ?? ""
            )
            payload["agent_name"] = identity.agentName
            if payload["title"] == nil || payload["title"]?.isEmpty == true {
                payload["title"] = identity.agentName
            }
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
        if let resolvedSubagent = resolveSubagentInvocation(toolName: toolName, payload: args) {
            return SubagentExecutionIdentityBuilder.make(
                role: resolvedSubagent.role,
                task: args["task"] ?? args["prompt"] ?? ""
            ).agentName
        }
        let pathComponent = { (key: String) -> String in
            ((args[key] ?? "") as NSString).lastPathComponent
        }
        let key = AgentToolUIDisplayName.normalizedRuntimeKey(toolName)
        switch key {
        case "bash", "command_execution":
            return AgentToolUIDisplayName.label(forRuntimeTool: key)
        case "edit", "str_replace":
            let file = pathComponent("path")
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: file.isEmpty ? nil : file
            )
        case "write", "write_file", "create_file":
            let file = pathComponent("path")
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: file.isEmpty ? nil : file
            )
        case "read", "read_file", "read_range":
            let file = pathComponent("path")
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: file.isEmpty ? nil : file
            )
        case "glob", "find_files":
            let pattern = args["pattern"] ?? ""
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: pattern.isEmpty ? nil : pattern
            )
        case "grep", "instant_grep", "rg":
            let query = args["query"] ?? ""
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: query.isEmpty ? nil : query
            )
        case "semantic_search", "codebase_search", "find_symbol", "find_references",
             "web_search", "web_fetch", "diagnostics", "build_project", "run_tests", "run_single_test":
            return AgentToolUIDisplayName.label(forRuntimeTool: key)
        case "skill":
            let name = args["skill"] ?? args["name"] ?? ""
            return AgentToolUIDisplayName.titled(
                AgentToolUIDisplayName.label(forRuntimeTool: key),
                detail: name.isEmpty ? nil : name
            )
        default:
            return AgentToolUIDisplayName.label(forRuntimeTool: toolName)
        }
    }

    // MARK: - Inline Subagent Execution

    /// Execute a subagent tool inline during the agent's streaming loop.

}
