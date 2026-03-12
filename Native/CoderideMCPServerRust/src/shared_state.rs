use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;

pub fn read_todos_text() -> String {
    let todos = read_todos();
    if todos.is_empty() {
        return "No todos found.".to_string();
    }

    let mut lines = Vec::new();
    let mut done_count = 0usize;
    for todo in &todos {
        let title = string_field(&todo, "title").unwrap_or("(untitled)");
        let status = string_field(&todo, "status").unwrap_or("pending");
        let priority = string_field(&todo, "priority").unwrap_or("medium");
        let active_form = string_field(&todo, "activeForm").unwrap_or("");
        let icon = match status {
            "done" => {
                done_count += 1;
                "[x]"
            }
            "in_progress" => "[~]",
            "blocked" => "[!]",
            _ => "[ ]",
        };
        let form_suffix = if status == "in_progress" && !active_form.is_empty() {
            format!(" — {active_form}")
        } else {
            String::new()
        };
        let files = todo
            .get("linkedFiles")
            .and_then(Value::as_array)
            .map(|items| {
                items.iter().filter_map(Value::as_str).collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let files_suffix = if files.is_empty() {
            String::new()
        } else {
            format!(" [files: {}]", files.join(", "))
        };
        lines.push(format!("{icon} {title}{form_suffix} ({priority}){files_suffix}"));
    }
    lines.push(format!("--- {} total, {} done ---", todos.len(), done_count));
    lines.join("\n")
}

pub fn write_todos(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let todos_value = arguments.get("todos");
    let title_raw = string_argument(arguments, "title");
    if todos_value.is_none() && title_raw.is_empty() {
        return Err("Error: provide either 'todos' (JSON array) or 'title' parameter".to_string());
    }

    if let Some(todos_value) = todos_value {
        if todos_value.is_array() {
            let items = todos_value.as_array().cloned().unwrap_or_default();
            write_json_array(items)?;
            return Ok("OK — todo list updated".to_string());
        }
        if todos_value.is_object() {
            write_json_array(vec![todos_value.clone()])?;
            return Ok("OK — todo list updated".to_string());
        }
        if let Some(text) = todos_value.as_str() {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                return Ok("OK — empty todo list received, clear request acknowledged".to_string());
            }
            if trimmed.starts_with('[') || trimmed.starts_with('{') {
                let parsed: Value = serde_json::from_str(trimmed)
                    .map_err(|_| "Error: 'todos' must be valid JSON".to_string())?;
                if parsed.is_array() {
                    write_json_array(parsed.as_array().cloned().unwrap_or_default())?;
                } else if parsed.is_object() {
                    write_json_array(vec![parsed])?;
                } else {
                    return Err("Error: 'todos' must be a JSON array or object".to_string());
                }
                return Ok("OK — todo list updated".to_string());
            }
        }
    }

    let item = json!({
        "id": format!("rust-{}", uuid_like_seed(&title_raw)),
        "title": title_raw,
        "status": normalize_status(&string_argument(arguments, "status")),
        "priority": normalize_priority(&string_argument(arguments, "priority")),
        "notes": string_argument(arguments, "notes"),
        "activeForm": string_argument(arguments, "activeForm"),
        "linkedFiles": arguments.get("linkedFiles").cloned().unwrap_or_else(|| Value::Array(vec![])),
        "source": "rust-mcp",
    });
    write_json_array(vec![item])?;
    Ok("OK — todo list updated".to_string())
}

fn write_json_array(items: Vec<Value>) -> Result<(), String> {
    let path = todos_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(&items).map_err(|error| error.to_string())?;
    fs::write(path, data).map_err(|error| error.to_string())
}

fn read_todos() -> Vec<Value> {
    let path = todos_file_path();
    let Ok(data) = fs::read(path) else { return Vec::new() };
    serde_json::from_slice::<Vec<Value>>(&data).unwrap_or_default()
}

fn todos_file_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared")
        .join("todos.json")
}

fn normalize_status(raw: &str) -> &'static str {
    match raw.trim().to_lowercase().as_str() {
        "done" | "completed" | "complete" | "finished" => "done",
        "in_progress" | "running" | "active" | "doing" | "started" => "in_progress",
        "blocked" | "failed" | "error" | "stuck" | "cancelled" | "canceled" | "aborted" | "skipped" => "blocked",
        _ => "pending",
    }
}

fn normalize_priority(raw: &str) -> &'static str {
    match raw.trim().to_lowercase().as_str() {
        "low" => "low",
        "high" => "high",
        _ => "medium",
    }
}

fn string_field<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn string_argument(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn uuid_like_seed(title: &str) -> String {
    let mut hash: u64 = 1469598103934665603;
    for byte in title.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    format!("{hash:016x}")
}
