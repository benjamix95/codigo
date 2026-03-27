use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub fn handle(
    name: &str,
    _workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    if !name.starts_with("coderide_subagent_") {
        return None;
    }
    Some(subagent_ack(name, arguments))
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    name.starts_with("coderide_subagent_")
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
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}
