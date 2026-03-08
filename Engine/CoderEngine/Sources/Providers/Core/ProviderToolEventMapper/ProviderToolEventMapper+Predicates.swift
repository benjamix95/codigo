import Foundation

extension ProviderToolEventMapper {
    static func isCommandTool(tool: String, payload: [String: Any], typeHint: String) -> Bool {
        if tool == "bash" || tool == "command_execution" {
            return true
        }
        if typeHint.contains("command") || typeHint.contains("bash") {
            return true
        }
        return firstString(in: payload, keys: ["command", "command_line", "cmd"]) != nil
    }

    static func isReadTool(_ tool: String) -> Bool {
        [
            "read", "read_file", "notebookread", "notebook_read", "read_range",
            "file_read", "fetch_file",
        ].contains(tool)
    }

    static func isFileChangeTool(_ tool: String, typeHint: String) -> Bool {
        if [
            "edit", "write", "write_file", "multiedit", "multi_edit", "create_file", "delete_file",
            "str_replace", "regex_replace", "parallel_apply", "apply_patch", "rename_symbol",
            "find_and_replace_all", "undo_edit", "notebook_edit", "notebook_write",
        ].contains(tool) {
            return true
        }
        return typeHint.contains("file_change") || typeHint.contains("edit") || typeHint.contains("write")
    }

    static func isSearchTool(_ tool: String) -> Bool {
        [
            "grep", "search", "instant_grep", "rg", "glob", "ls", "list_dir", "find_files",
        ].contains(tool)
    }

    static func isSemanticTool(_ tool: String) -> Bool {
        [
            "semantic_search", "codebase_search", "find_symbol", "find_references",
            "file_outline", "list_symbols",
        ].contains(tool)
    }

    static func isMCPTool(_ tool: String, payload: [String: Any]) -> Bool {
        if let marker = firstString(in: payload, keys: ["is_mcp"]),
           ["1", "true", "yes"].contains(marker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return true
        }
        let explicitMCPTools: Set<String> = [
            "mcp", "mcp_call", "mcp_list_tools", "mcp_list_servers",
            "mcp_describe_tool", "mcp_health", "mcp_reconnect",
            "mcp_batch", "mcp_read_resource", "mcp_subscribe",
            "mcp_list_prompts", "mcp_get_prompt", "mcp_logs", "mcp_restart_server"
        ]
        if explicitMCPTools.contains(tool) {
            return true
        }
        if firstString(in: payload, keys: ["mcp_tool", "mcp_server", "server_id"]) != nil {
            return true
        }
        return false
    }

    static func isWebSearchTool(_ tool: String, payload _: [String: Any]) -> Bool {
        tool.hasPrefix("web_search")
    }

    static func isWebFetchTool(_ tool: String, payload _: [String: Any]) -> Bool {
        tool.hasPrefix("web_fetch")
    }

    static func isSkillTool(_ tool: String) -> Bool {
        tool == "skill" || tool.hasPrefix("skill_")
    }

    static func isTodoTool(_ tool: String) -> Bool {
        tool == "todo_write" || tool == "todo_read"
    }

    static func isIDEStateTool(_ tool: String) -> Bool {
        IDEStateSyntheticEventFactory.knowsTool(tool)
    }

    static func isDebugTool(_ tool: String) -> Bool {
        [
            "debug_context", "debug_log", "debug_query", "debug_session",
            "debug_hypothesize", "debug_mark", "debug_clean", "debug_trace_analyze",
            "debug_instrument", "debug_timeline", "debug_snapshot", "debug_test_check",
        ].contains(tool)
    }

    static func isAgentTool(_ tool: String) -> Bool {
        if ["task", "sub_agent", "subagent", "agent", "run_agent"].contains(tool) {
            return true
        }
        return tool.hasPrefix("subagent_")
    }
}
