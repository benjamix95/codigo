import Foundation

/// Etichette solo UI per gli strumenti dell'agente. Gli identificatori runtime e gli schemi API restano invariati.
public enum AgentToolUIDisplayName {
    public static func normalizedRuntimeKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return ProviderToolEventMapper.normalizeToolIdentifier(trimmed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Titolo breve per timeline, attività e chiamate MCP.
    public static func label(forRuntimeTool rawName: String) -> String {
        let key = normalizedRuntimeKey(rawName)
        guard !key.isEmpty else { return "Tool" }

        if let role = SubagentRole.fromToolName(key) {
            return "\(role.displayName) subagent"
        }

        switch key {
        case "bash", "command_execution":
            return "Terminal command"
        case "grep", "instant_grep", "rg":
            return "Grep in workspace"
        case "write", "write_file":
            return "Write to workspace file"
        case "create_file":
            return "Create workspace file"
        case "read", "read_file", "file_read":
            return "Read workspace file"
        case "read_range", "fetch_file":
            return "Read file range"
        case "batch_read":
            return "Read file batch"
        case "edit":
            return "Edit workspace file"
        case "str_replace":
            return "Replace text in file"
        case "regex_replace", "find_and_replace_all":
            return "Regex replace in files"
        case "delete_file":
            return "Delete workspace file"
        case "glob", "find_files":
            return "Find files by pattern"
        case "list_dir":
            return "List folder contents"
        case "semantic_search":
            return "Semantic search"
        case "codebase_search":
            return "Codebase search"
        case "find_symbol":
            return "Find symbol"
        case "find_references":
            return "Find references"
        case "search", "search_symbols", "search_health_check":
            return "Search in workspace"
        case "web_search":
            return "Web search"
        case "web_fetch":
            return "Fetch web page"
        case "diagnostics", "read_lints":
            return "Diagnostics"
        case "build_project":
            return "Build project"
        case "run_tests", "run_single_test":
            return "Run tests"
        case "skill":
            return "Run skill"
        case "todo_write":
            return "Update task list"
        case "todo_read":
            return "Read task list"
        case "parallel_apply", "multiedit", "multi_edit":
            return "Multi-file edits"
        case "apply_patch":
            return "Apply patch"
        case "rename_symbol":
            return "Rename symbol"
        case "undo_edit":
            return "Undo edit"
        case "notebook_edit", "notebook_write", "notebook_read", "notebookread":
            return "Notebook"
        case "file_outline":
            return "File outline"
        case "list_symbols":
            return "List symbols"
        case "attempt_completion":
            return "Complete task"
        case "policy_ack":
            return "Policy acknowledged"
        case "mcp_call":
            return "MCP call"
        case "plan_create":
            return "Create plan"
        case "plan_read":
            return "Read plan"
        case "plan_step_upsert":
            return "Update plan step"
        case "plan_step_batch_update":
            return "Update plan steps"
        case "plan_step_reorder":
            return "Reorder plan steps"
        case "plan_step_dependency_set":
            return "Set plan step dependencies"
        case "plan_set_walkthrough":
            return "Update plan walkthrough"
        case "plan_history_read":
            return "Read plan history"
        case "plan_diff":
            return "Plan diff"
        case "plan_request_user_input":
            return "Plan clarification request"
        case "code_context":
            return "Code context"
        case "tool_search":
            return "Tool search"
        case "git_status", "git_diff", "git_show", "git_log_search":
            return humanizedFallback(key)
        default:
            return humanizedFallback(key)
        }
    }

    public static func titled(_ base: String, detail: String?) -> String {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return base }
        return "\(base) • \(trimmed)"
    }

    private static func humanizedFallback(_ key: String) -> String {
        if key.hasPrefix("mcp_") {
            let rest = String(key.dropFirst(4))
            if rest.isEmpty { return "MCP" }
            return "MCP \(titleCaseWords(rest))"
        }
        if key.hasPrefix("plan_") {
            let rest = String(key.dropFirst(5))
            if rest.isEmpty { return "Plan" }
            return "Plan \(titleCaseWords(rest))"
        }
        if key.hasPrefix("debug_") {
            let rest = String(key.dropFirst(6))
            if rest.isEmpty { return "Debug" }
            return "Debug \(titleCaseWords(rest))"
        }
        if key.hasPrefix("coderide_") {
            let rest = String(key.dropFirst("coderide_".count))
            if rest.isEmpty { return "CoderIDE" }
            return "CoderIDE \(titleCaseWords(rest))"
        }
        return titleCaseWords(key)
    }

    private static func titleCaseWords(_ key: String) -> String {
        key
            .split(separator: "_")
            .map(\.capitalized)
            .joined(separator: " ")
    }
}
