use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub fn handle(
    name: &str,
    _workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_show_task_panel" => Some(CallToolResult::text("OK — task panel shown")),
        "coderide_show_swarm_panel" => Some(CallToolResult::text("OK — swarm panel opened")),
        "coderide_activate_plan_mode" => Some(CallToolResult::text("OK — plan mode activated")),
        "coderide_activate_debug_mode" => Some(CallToolResult::text("OK — debug mode activated")),
        "coderide_policy_ack" => Some(CallToolResult::text("OK — policy acknowledged")),
        "coderide_mermaid_render" => Some(mermaid_render(arguments)),
        _ => None,
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    matches!(
        name,
        "coderide_show_task_panel"
            | "coderide_show_swarm_panel"
            | "coderide_activate_plan_mode"
            | "coderide_activate_debug_mode"
            | "coderide_policy_ack"
            | "coderide_mermaid_render"
    )
}

fn mermaid_render(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    if non_empty(string_arg(arguments, "code")).is_none() {
        return CallToolResult::error(
            "Error: 'code' parameter is required and must contain valid mermaid syntax",
        );
    }
    let title = non_empty(string_arg(arguments, "title"))
        .map(|value| format!(" ({value})"))
        .unwrap_or_default();
    CallToolResult::text(format!("OK — mermaid diagram rendered in IDE{title}"))
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .map(json_value_to_string)
        .unwrap_or_default()
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
