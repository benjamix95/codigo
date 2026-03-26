use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::file_lock::{with_file_lock, LockMode};

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
            .map(|items| items.iter().filter_map(Value::as_str).collect::<Vec<_>>())
            .unwrap_or_default();
        let files_suffix = if files.is_empty() {
            String::new()
        } else {
            format!(" [files: {}]", files.join(", "))
        };
        lines.push(format!(
            "{icon} {title}{form_suffix} ({priority}){files_suffix}"
        ));
    }
    lines.push(format!(
        "--- {} total, {} done ---",
        todos.len(),
        done_count
    ));
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
        "id": format!("rust-{}", unique_id()),
        "title": title_raw,
        "status": normalize_status(&string_argument(arguments, "status")),
        "priority": normalize_priority(&string_argument(arguments, "priority")),
        "notes": string_argument(arguments, "notes"),
        "activeForm": string_argument(arguments, "activeForm"),
        "linkedFiles": arguments.get("linkedFiles").cloned().unwrap_or_else(|| Value::Array(vec![])),
        "source": "rust-mcp",
    });
    // Protect read-modify-write with exclusive file lock to prevent
    // cross-process TOCTOU race (Swift app + Rust MCP server).
    with_file_lock(&todos_file_path(), LockMode::Exclusive, || {
        let mut existing = read_todos();
        existing.push(item.clone());
        write_json_array(existing)
    })?;
    Ok("OK — todo list updated".to_string())
}

fn write_json_array(items: Vec<Value>) -> Result<(), String> {
    let path = todos_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(&items).map_err(|error| error.to_string())?;
    // Atomic write: write to temp file then rename to avoid partial writes and races.
    let tmp_path = path.with_extension("json.tmp");
    fs::write(&tmp_path, &data).map_err(|error| error.to_string())?;
    fs::rename(&tmp_path, &path).map_err(|error| error.to_string())
}

fn read_todos() -> Vec<Value> {
    let path = todos_file_path();
    let Ok(data) = fs::read(path) else {
        return Vec::new();
    };
    match serde_json::from_slice::<Vec<Value>>(&data) {
        Ok(items) => items,
        Err(e) => {
            eprintln!(
                "[shared_state] todos.json parse error (returning empty list): {e}"
            );
            Vec::new()
        }
    }
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
        "blocked" | "failed" | "error" | "stuck" | "cancelled" | "canceled" | "aborted"
        | "skipped" => "blocked",
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

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn unique_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;
    let seq = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{nanos:016x}-{seq:04x}")
}
