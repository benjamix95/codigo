use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_read" => Some(file_read(workspace, arguments)),
        "coderide_list_dir" => Some(list_dir(workspace, arguments)),
        _ => None,
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    matches!(name, "coderide_read" | "coderide_list_dir")
}

fn file_read(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let Ok(content) = fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let offset = int_arg(arguments, "offset").unwrap_or(1).max(1) as usize;
    let limit = int_arg(arguments, "limit").unwrap_or(200).max(1) as usize;
    let lines = content
        .lines()
        .skip(offset - 1)
        .take(limit)
        .collect::<Vec<_>>();
    CallToolResult::text(lines.join("\n"))
}

fn list_dir(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let Ok(entries) = fs::read_dir(&path) else {
        return CallToolResult::error(format!("Error: unable to list '{}'", path.display()));
    };
    let mut lines = entries
        .flatten()
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect::<Vec<_>>();
    lines.sort();
    CallToolResult::text(lines.join("\n"))
}

fn resolve_path(workspace: &Path, input: String) -> PathBuf {
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
