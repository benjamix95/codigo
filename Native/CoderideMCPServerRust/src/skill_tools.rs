use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

pub fn handle(
    name: &str,
    _workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    if name != "coderide_skill" {
        return None;
    }
    let skill = string_arg(arguments, "skill")
        .or_else(|| string_arg(arguments, "name"))
        .or_else(|| string_arg(arguments, "task"));
    let Some(skill) = skill else {
        return Some(CallToolResult::error(
            "Error: 'skill' parameter is required",
        ));
    };
    let task = string_arg(arguments, "task")
        .or_else(|| string_arg(arguments, "args"))
        .unwrap_or_default();
    let path = std::env::var("HOME")
        .ok()
        .map(|home| format!("{home}/.codex/skills/{skill}/SKILL.md"));
    let detail = path
        .as_deref()
        .and_then(|path| fs::read_to_string(path).ok())
        .map(|content| {
            let summary = content.lines().take(8).collect::<Vec<_>>().join("\n");
            if task.is_empty() {
                format!("Skill {skill} loaded\n{summary}")
            } else {
                format!("Skill {skill} loaded for task: {task}\n{summary}")
            }
        })
        .unwrap_or_else(|| {
            if task.is_empty() {
                format!("OK — skill {skill} queued")
            } else {
                format!("OK — skill {skill} queued for task: {task}")
            }
        });
    Some(CallToolResult::text(detail))
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<String> {
    let value = arguments
        .get(key)
        .and_then(Value::as_str)?
        .trim()
        .to_string();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}
