import Foundation

extension UnifiedToolRuntime {
    static let preferredRustAliasTools: Set<String> = [
        "activate_debug_mode", "activate_plan_mode",
        "codebase_search", "create_file",
        "debug_clean", "debug_context", "debug_hypothesize", "debug_instrument",
        "debug_log", "debug_mark", "debug_query", "debug_request_user",
        "debug_resolve", "debug_session", "debug_set_phase", "debug_snapshot",
        "debug_test_check", "debug_timeline", "debug_trace_analyze",
        "diagnostics", "file_outline", "find_files", "find_references", "find_symbol",
        "git_diff", "glob", "grep",
        "list_dir", "mermaid_render",
        "plan_create", "plan_diff", "plan_history_read", "plan_read",
        "plan_request_user_input", "plan_set_walkthrough",
        "plan_step_batch_update", "plan_step_dependency_set",
        "plan_step_reorder", "plan_step_update", "plan_step_upsert",
        "policy_ack", "read", "read_lints", "read_range",
        "regex_replace", "semantic_search", "show_swarm_panel", "show_task_panel",
        "skill", "str_replace",
        "subagent_bughunter", "subagent_coder", "subagent_debugger",
        "subagent_docwriter", "subagent_explorer", "subagent_reviewer",
        "subagent_securityauditor", "subagent_testwriter",
        "todo_read", "todo_write", "write",
    ]

    func preferredRustAliasRoute(for toolName: String) -> (serverId: String, toolName: String)? {
        guard Self.preferredRustAliasTools.contains(toolName) else { return nil }
        return MCPNativeToolRegistry.shared.aliasRoute(for: toolName)
    }
}
