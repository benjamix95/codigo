use crate::audit_tools;
use crate::debug_tools;
use crate::diagnostics_tools;
use crate::edit_tools;
use crate::plan_state;
use crate::review_tools;
use crate::search_tools;
use crate::shared_state;
use crate::skill_tools;
use crate::web_tools;
use app_core_protocol::mcp::{CallToolResult, ToolCallParams};
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

pub fn handle_tool_call(workspace: &Path, params: ToolCallParams) -> CallToolResult {
    let arguments = params.arguments.unwrap_or_default();
    if let Some(result) = audit_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = diagnostics_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = debug_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = edit_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = search_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = web_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = skill_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    if let Some(result) = review_tools::handle(params.name.as_str(), workspace, &arguments) {
        return result;
    }
    match params.name.as_str() {
        "coderide_todo_read" => CallToolResult::text(shared_state::read_todos_text()),
        "coderide_todo_write" => match shared_state::write_todos(&arguments) {
            Ok(message) => CallToolResult::text(message),
            Err(message) => CallToolResult::error(message),
        },
        "coderide_show_task_panel" => CallToolResult::text("OK — task panel shown"),
        "coderide_show_swarm_panel" => CallToolResult::text("OK — swarm panel opened"),
        "coderide_activate_plan_mode" => CallToolResult::text("OK — plan mode activated"),
        "coderide_activate_debug_mode" => CallToolResult::text("OK — debug mode activated"),
        "coderide_policy_ack" => CallToolResult::text("OK — policy acknowledged"),
        "coderide_mermaid_render" => mermaid_render(&arguments),
        "coderide_debug_set_phase" => debug_set_phase(&arguments),
        "coderide_debug_request_user" => debug_request_user(&arguments),
        "coderide_debug_resolve" => CallToolResult::text("OK — debug session resolved"),
        "coderide_debug_session" => CallToolResult::text("OK — debug session updated"),
        "coderide_plan_create" => wrap(plan_state::create_snapshot(&arguments)),
        "coderide_plan_read" => wrap(plan_state::read_latest(&arguments)),
        "coderide_plan_history_read" => wrap(plan_state::read_history(&arguments)),
        "coderide_plan_step_update" => wrap(plan_state::step_update(&arguments)),
        "coderide_plan_step_upsert" => wrap(plan_state::step_upsert(&arguments)),
        "coderide_plan_step_batch_update" => wrap(plan_state::step_batch_update(&arguments)),
        "coderide_plan_step_reorder" => wrap(plan_state::step_reorder(&arguments)),
        "coderide_plan_step_dependency_set" => wrap(plan_state::step_dependency_set(&arguments)),
        "coderide_plan_set_walkthrough" => wrap(plan_state::set_walkthrough(&arguments)),
        "coderide_plan_diff" => wrap(plan_state::diff(&arguments)),
        "coderide_plan_request_user_input" => wrap(plan_state::request_user_input(&arguments)),
        "coderide_read" => file_read(workspace, &arguments),
        "coderide_list_dir" => list_dir(workspace, &arguments),
        "coderide_glob" => glob(workspace, &arguments),
        "coderide_grep" => grep(workspace, &arguments),
        name if name.starts_with("coderide_subagent_") => subagent_ack(name, &arguments),
        name => CallToolResult::error(format!("tool not yet migrated to rust server: {name}")),
    }
}

fn file_read(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let Ok(content) = std::fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let offset = int_arg(arguments, "offset").unwrap_or(1).max(1) as usize;
    let limit = int_arg(arguments, "limit").unwrap_or(200).max(1) as usize;
    let lines = content.lines().skip(offset - 1).take(limit).collect::<Vec<_>>();
    CallToolResult::text(lines.join("\n"))
}

fn list_dir(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let Ok(entries) = std::fs::read_dir(&path) else {
        return CallToolResult::error(format!("Error: unable to list '{}'", path.display()));
    };
    let mut lines = entries
        .flatten()
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect::<Vec<_>>();
    lines.sort();
    CallToolResult::text(lines.join("\n"))
}

fn glob(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let pattern = non_empty(string_arg(arguments, "pattern"));
    let Some(pattern) = pattern else {
        return CallToolResult::error("Error: 'pattern' parameter is required");
    };
    run_rg(workspace, &["--files", "-g", &pattern])
}

fn grep(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = non_empty(string_arg(arguments, "query")).or_else(|| non_empty(string_arg(arguments, "pattern")));
    let Some(query) = query else {
        return CallToolResult::error("Error: 'query' parameter is required");
    };
    run_rg(workspace, &["-n", "--no-heading", &query])
}

fn run_rg(workspace: &Path, args: &[&str]) -> CallToolResult {
    let output = Command::new("rg").args(args).current_dir(workspace).output();
    match output {
        Ok(output) if output.status.success() || output.status.code() == Some(1) => {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if text.is_empty() {
                CallToolResult::text("No matches found.")
            } else {
                CallToolResult::text(text)
            }
        }
        Ok(output) => CallToolResult::error(String::from_utf8_lossy(&output.stderr).trim().to_string()),
        Err(error) => CallToolResult::error(format!("Error: failed to execute rg: {error}")),
    }
}

fn subagent_ack(name: &str, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    if non_empty(string_arg(arguments, "task")).is_none() {
        return CallToolResult::error("Error: 'task' parameter is required");
    }
    let role = match name.trim_start_matches("coderide_subagent_") {
        "explorer" => "Explorer",
        "reviewer" => "Reviewer",
        "coder" => "Coder",
        "debugger" => "Debugger",
        "docWriter" => "Doc Writer",
        "testWriter" => "Test Writer",
        "securityAuditor" => "Security Auditor",
        "bugHunter" => "Bug Hunter",
        other => other,
    };
    CallToolResult::text(format!("OK — subagent {role} launched"))
}

fn debug_set_phase(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let phase = string_arg(arguments, "phase").to_lowercase();
    let valid = ["describing", "reproducing", "fixing", "instrumenting", "verifying", "resolved"];
    if phase.is_empty() {
        return CallToolResult::error("Error: 'phase' parameter is required");
    }
    if !valid.contains(&phase.as_str()) {
        return CallToolResult::error(format!("Error: invalid phase '{phase}'. Use: {}", valid.join(", ")));
    }
    CallToolResult::text(format!("OK — debug phase set to {phase}"))
}

fn debug_request_user(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let kind = string_arg(arguments, "kind").to_lowercase();
    let prompt = string_arg(arguments, "prompt");
    if kind.is_empty() || prompt.is_empty() {
        return CallToolResult::error("Error: 'kind' and 'prompt' are required");
    }
    if !["question", "reproduce"].contains(&kind.as_str()) {
        return CallToolResult::error("Error: invalid kind. Use: question or reproduce");
    }
    CallToolResult::text(format!("OK — debug user request queued ({kind})"))
}

fn mermaid_render(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    if non_empty(string_arg(arguments, "code")).is_none() {
        return CallToolResult::error("Error: 'code' parameter is required and must contain valid mermaid syntax");
    }
    let title = non_empty(string_arg(arguments, "title"))
        .map(|value| format!(" ({value})"))
        .unwrap_or_default();
    CallToolResult::text(format!("OK — mermaid diagram rendered in IDE{title}"))
}

fn resolve_path(workspace: &Path, input: String) -> std::path::PathBuf {
    let path = Path::new(input.trim());
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        workspace.join(path)
    }
}

fn int_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    arguments.get(key).and_then(Value::as_i64)
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments.get(key).map(json_value_to_string).unwrap_or_default()
}

fn json_value_to_string(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Bool(flag) => flag.to_string(),
        Value::Number(number) => number.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

fn non_empty(value: String) -> Option<String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() { None } else { Some(trimmed) }
}

fn wrap(result: Result<String, String>) -> CallToolResult {
    match result {
        Ok(message) => CallToolResult::text(message),
        Err(message) => CallToolResult::error(message),
    }
}
