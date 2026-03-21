import Foundation

extension ProviderToolEventMapper {
    private enum MappingRoute {
        case command
        case read
        case fileChange
        case semantic
        case search
        case mcp
        case debug
        case webSearch
        case webFetch
        case skill
        case agent
        case todo
        case ideState
    }

    /// Explicit declarative mapping table `input_tool -> routing category`.
    /// Heuristic fallback remains only for backward-compatible payloads.
    private static let declaredRoutes: [String: MappingRoute] = [
        "bash": .command,
        "command_execution": .command,
        "read": .read,
        "read_file": .read,
        "fetch_file": .read,
        "read_range": .read,
        "file_read": .read,
        "notebookread": .read,
        "notebook_read": .read,
        "edit": .fileChange,
        "write": .fileChange,
        "write_file": .fileChange,
        "multiedit": .fileChange,
        "multi_edit": .fileChange,
        "create_file": .fileChange,
        "delete_file": .fileChange,
        "str_replace": .fileChange,
        "regex_replace": .fileChange,
        "parallel_apply": .fileChange,
        "apply_patch": .fileChange,
        "rename_symbol": .fileChange,
        "find_and_replace_all": .fileChange,
        "undo_edit": .fileChange,
        "notebook_edit": .fileChange,
        "notebook_write": .fileChange,
        "semantic_search": .semantic,
        "codebase_search": .semantic,
        "find_symbol": .semantic,
        "find_references": .semantic,
        "file_outline": .semantic,
        "list_symbols": .semantic,
        "grep": .search,
        "search": .search,
        "instant_grep": .search,
        "rg": .search,
        "glob": .search,
        "ls": .search,
        "list_dir": .search,
        "find_files": .search,
        "mcp": .mcp,
        "mcp_call": .mcp,
        "mcp_list_servers": .mcp,
        "mcp_list_tools": .mcp,
        "mcp_describe_tool": .mcp,
        "mcp_health": .mcp,
        "mcp_reconnect": .mcp,
        "web_search": .webSearch,
        "web_search_started": .webSearch,
        "web_search_completed": .webSearch,
        "web_search_failed": .webSearch,
        "web_fetch": .webFetch,
        "web_fetch_started": .webFetch,
        "web_fetch_completed": .webFetch,
        "web_fetch_failed": .webFetch,
        "skill": .skill,
        "agent": .agent,
        "run_agent": .agent,
        "sub_agent": .agent,
        "subagent": .agent,
        "task": .agent,
        "todo_write": .todo,
        "todo_read": .todo,
        "debug_context": .debug,
        "debug_log": .debug,
        "debug_query": .debug,
        "debug_session": .debug,
        "debug_hypothesize": .debug,
        "debug_mark": .debug,
        "debug_clean": .debug,
        "debug_trace_analyze": .debug,
        "debug_instrument": .debug,
        "debug_timeline": .debug,
        "debug_snapshot": .debug,
        "debug_test_check": .debug,
        "debug_set_phase": .ideState,
        "debug_request_user": .ideState,
        "debug_resolve": .ideState,
        "policy_ack": .ideState,
        "mermaid_render": .ideState,
        "activate_plan_mode": .ideState,
        "activate_debug_mode": .ideState,
        "show_task_panel": .ideState,
        "show_swarm_panel": .ideState,
        "plan_step_update": .ideState,
        "plan_create": .ideState,
        "plan_read": .ideState,
        "plan_step_upsert": .ideState,
        "plan_step_batch_update": .ideState,
        "plan_step_reorder": .ideState,
        "plan_step_dependency_set": .ideState,
        "plan_set_walkthrough": .ideState,
        "plan_history_read": .ideState,
        "plan_diff": .ideState,
        "plan_request_user_input": .ideState,
    ]

    static func map(
        toolName rawToolName: String,
        payload: [String: Any],
        typeHint: String? = nil
    ) -> (type: String, payload: [String: String])? {
        let normalizedPayload = expandedPayload(payload)
        let normalizedTool = normalizeToolIdentifier(rawToolName)
        let normalizedHint = normalizeToolIdentifier(typeHint ?? "")
        let tool = normalizedTool.isEmpty ? normalizedHint : normalizedTool

        let mappedToolName = tool.isEmpty ? rawToolName : tool
        if tool == "debug_panel" || normalizedHint == "debug_panel" {
            return (
                "tool_validation_error",
                [
                    "title": "Legacy debug_panel is not supported",
                    "detail": "Use debug_set_phase, debug_request_user, debug_resolve",
                    "status": "failed",
                    "error_code": "legacy_debug_panel_removed",
                    "tool": "debug_panel",
                ]
            )
        }

        if let declared = declaredRoutes[tool] {
            return mapViaDeclaredRoute(
                route: declared,
                tool: mappedToolName,
                payload: normalizedPayload,
                typeHint: normalizedHint
            )
        }

        if isCommandTool(tool: tool, payload: normalizedPayload, typeHint: normalizedHint) {
            return mapCommand(tool: mappedToolName, payload: normalizedPayload)
        }
        if isReadTool(tool) {
            return mapRead(tool: mappedToolName, payload: normalizedPayload)
        }
        if isFileChangeTool(tool, typeHint: normalizedHint) {
            return mapFileChange(tool: mappedToolName, payload: normalizedPayload, typeHint: normalizedHint)
        }
        if isSemanticTool(tool) {
            return mapSemantic(tool: mappedToolName, payload: normalizedPayload)
        }
        if isSearchTool(tool) {
            return mapSearch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isMCPTool(tool, payload: normalizedPayload) {
            if let ideRemap = remapMCPIDEStateTool(tool: mappedToolName, payload: normalizedPayload) {
                return ideRemap
            }
            return mapMCP(tool: mappedToolName, payload: normalizedPayload)
        }
        if isWebSearchTool(tool, payload: normalizedPayload) {
            return mapWebSearch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isWebFetchTool(tool, payload: normalizedPayload) {
            return mapWebFetch(tool: mappedToolName, payload: normalizedPayload)
        }
        if isSkillTool(tool) {
            return mapSkill(tool: mappedToolName, payload: normalizedPayload)
        }
        if isAgentTool(tool) {
            return mapAgent(tool: mappedToolName, payload: normalizedPayload)
        }
        if isTodoTool(tool) {
            return mapTodo(tool: mappedToolName, payload: normalizedPayload)
        }
        if isIDEStateTool(tool) {
            return mapIDEState(tool: tool, payload: normalizedPayload)
        }
        if !tool.isEmpty {
            return mapFallback(tool: mappedToolName, payload: normalizedPayload)
        }
        return nil
    }

    private static func mapViaDeclaredRoute(
        route: MappingRoute,
        tool rawToolName: String,
        payload: [String: Any],
        typeHint: String
    ) -> (type: String, payload: [String: String])? {
        switch route {
        case .command:
            return mapCommand(tool: rawToolName, payload: payload)
        case .read:
            return mapRead(tool: rawToolName, payload: payload)
        case .fileChange:
            return mapFileChange(tool: rawToolName, payload: payload, typeHint: typeHint)
        case .semantic:
            return mapSemantic(tool: rawToolName, payload: payload)
        case .search:
            return mapSearch(tool: rawToolName, payload: payload)
        case .mcp:
            if let ideRemap = remapMCPIDEStateTool(tool: rawToolName, payload: payload) {
                return ideRemap
            }
            return mapMCP(tool: rawToolName, payload: payload)
        case .debug:
            return mapDebug(tool: rawToolName, payload: payload)
        case .webSearch:
            return mapWebSearch(tool: rawToolName, payload: payload)
        case .webFetch:
            return mapWebFetch(tool: rawToolName, payload: payload)
        case .skill:
            return mapSkill(tool: rawToolName, payload: payload)
        case .agent:
            return mapAgent(tool: rawToolName, payload: payload)
        case .todo:
            return mapTodo(tool: rawToolName, payload: payload)
        case .ideState:
            return mapIDEState(tool: normalizeToolIdentifier(rawToolName), payload: payload)
        }
    }
}
