use crate::shared_state;
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
        "coderide_todo_read" => Some(CallToolResult::text(shared_state::read_todos_text())),
        "coderide_todo_write" => Some(match shared_state::write_todos(arguments) {
            Ok(message) => CallToolResult::text(message),
            Err(message) => CallToolResult::error(message),
        }),
        _ => None,
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    matches!(name, "coderide_todo_read" | "coderide_todo_write")
}
