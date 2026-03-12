use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use solocode_rust_core::review_audit::run_audit;
use std::collections::BTreeMap;
use std::path::Path;

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    if !name.starts_with("coderide_audit_") {
        return None;
    }
    let tool_name = name.trim_start_matches("coderide_");
    let scope_files = parse_scope_files(arguments);
    let result = run_audit(tool_name, scope_files, &workspace.display().to_string());
    Some(match result {
        Ok(value) => CallToolResult::text(
            serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string()),
        ),
        Err(message) if message == "unsupported_tool" => {
            CallToolResult::error("tool not implemented in rust core")
        }
        Err(message) => CallToolResult::error(message),
    })
}

fn parse_scope_files(arguments: &BTreeMap<String, Value>) -> Vec<String> {
    let value = arguments
        .get("scope_files")
        .or_else(|| arguments.get("scopeFiles"))
        .cloned()
        .unwrap_or_else(|| Value::Array(vec![]));
    match value {
        Value::Array(items) => items
            .iter()
            .filter_map(Value::as_str)
            .map(|text| text.trim().to_string())
            .filter(|text| !text.is_empty())
            .collect(),
        Value::String(text) if text.trim().starts_with('[') => {
            serde_json::from_str::<Value>(&text)
                .ok()
                .and_then(|parsed| parsed.as_array().cloned())
                .unwrap_or_default()
                .iter()
                .filter_map(Value::as_str)
                .map(|part| part.trim().to_string())
                .filter(|part| !part.is_empty())
                .collect()
        }
        Value::String(text) => text
            .split(',')
            .map(|part| part.trim().to_string())
            .filter(|part| !part.is_empty())
            .collect(),
        _ => vec![],
    }
}
