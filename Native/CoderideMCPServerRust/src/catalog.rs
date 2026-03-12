use app_core_protocol::mcp::ToolDefinition;

const TOOL_NAMES: &str = include_str!("tool_names.txt");

pub fn all_tools() -> Vec<ToolDefinition> {
    TOOL_NAMES
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(tool_definition)
        .collect()
}

fn tool_definition(name: &str) -> ToolDefinition {
    ToolDefinition::new(
        name.to_string(),
        Some(description_for(name).to_string()),
        is_read_only(name),
    )
}

fn description_for(name: &str) -> &'static str {
    match name {
        "coderide_read" => "Read a file from the current workspace",
        "coderide_list_dir" => "List files and directories in the current workspace",
        "coderide_glob" => "Find files matching a glob pattern",
        "coderide_grep" => "Search file contents using ripgrep-compatible semantics",
        "coderide_todo_read" => "Read the shared IDE todo list",
        "coderide_todo_write" => "Write or update items in the shared IDE todo list",
        "coderide_subagent_explorer" => "Launch an Explorer subagent",
        "coderide_subagent_reviewer" => "Launch a Reviewer subagent",
        "coderide_subagent_coder" => "Launch a Coder subagent",
        "coderide_subagent_debugger" => "Launch a Debugger subagent",
        "coderide_review_start" => "Queue a code review session",
        "coderide_review_status" => "Read the current code review status",
        "coderide_review_findings" => "List code review findings",
        "coderide_security_status" => "Read the current security review status",
        "coderide_bughunter_status" => "Read the current BugHunter status",
        _ => "Rust-migrated MCP tool",
    }
}

fn is_read_only(name: &str) -> bool {
    matches!(
        name,
        "coderide_read"
            | "coderide_list_dir"
            | "coderide_read_range"
            | "coderide_glob"
            | "coderide_grep"
            | "coderide_find_files"
            | "coderide_find_symbol"
            | "coderide_find_references"
            | "coderide_file_outline"
            | "coderide_codebase_search"
            | "coderide_semantic_search"
            | "coderide_read_lints"
            | "coderide_todo_read"
            | "coderide_plan_read"
            | "coderide_plan_diff"
            | "coderide_plan_history_read"
            | "coderide_review_status"
            | "coderide_review_findings"
            | "coderide_review_list_sessions"
            | "coderide_review_diff_summary"
            | "coderide_review_preview_patch"
            | "coderide_review_get_outcome"
            | "coderide_security_status"
            | "coderide_security_findings"
            | "coderide_security_preview_patch"
            | "coderide_bughunter_status"
            | "coderide_bughunter_findings"
            | "coderide_bughunter_run_history"
            | "coderide_bughunter_explain_cluster"
            | "coderide_web_fetch"
            | "coderide_web_search"
    )
}
