use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn handle_action(
    action: &str,
    arguments: &BTreeMap<String, String>,
) -> Result<String, String> {
    match action {
        "todo_read" => Ok(read_todos_text()),
        "todo_write" => write_todos(arguments),
        _ => Err(format!("Error: unsupported todo action '{action}'")),
    }
}

pub fn read_todos_text() -> String {
    let todos = read_todos();
    if todos.is_empty() {
        return "No todos found.".to_string();
    }

    let mut lines = Vec::new();
    let mut done_count = 0usize;
    for todo in &todos {
        let title = string_field(todo, "title").unwrap_or("(untitled)");
        let status = string_field(todo, "status").unwrap_or("pending");
        let priority = string_field(todo, "priority").unwrap_or("medium");
        let active_form = string_field(todo, "activeForm").unwrap_or("");
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
        lines.push(format!("{icon} {title}{form_suffix} ({priority}){files_suffix}"));
    }
    lines.push(format!("--- {} total, {} done ---", todos.len(), done_count));
    lines.join("\n")
}

pub fn write_todos(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let todos_raw = string_arg(arguments, "todos");
    let title_raw = string_arg(arguments, "title");
    if todos_raw.is_empty() && title_raw.is_empty() {
        return Err("Error: provide either 'todos' (JSON array) or 'title' parameter".to_string());
    }

    if !todos_raw.is_empty() {
        let trimmed = todos_raw.trim();
        if trimmed.is_empty() {
            write_json_array(vec![])?;
            return Ok("OK — empty todo list received, clear request acknowledged".to_string());
        }
        let parsed: Value = serde_json::from_str(trimmed)
            .map_err(|_| "Error: 'todos' must be a valid todo collection. Use a JSON array, a single JSON object, or a checklist string.".to_string())?;
        if let Some(items) = parsed.as_array() {
            write_json_array(items.clone())?;
            return Ok("OK — todo list updated".to_string());
        }
        if parsed.is_object() {
            write_json_array(vec![parsed])?;
            return Ok("OK — todo list updated".to_string());
        }
        return Err("Error: 'todos' must be a valid todo collection. Use a JSON array, a single JSON object, or a checklist string.".to_string());
    }

    let item = json!({
        "id": Value::Null,
        "title": title_raw,
        "status": normalize_status(&string_arg(arguments, "status")),
        "priority": normalize_priority(&string_arg(arguments, "priority")),
        "notes": string_arg(arguments, "notes"),
        "activeForm": string_arg(arguments, "activeForm"),
        "linkedFiles": parse_string_array(arguments.get("linkedFiles").map(String::as_str)).unwrap_or_default(),
        "source": "rust-mcp",
    });
    write_json_array(vec![item])?;
    Ok("OK — todo list updated".to_string())
}

pub fn read_todos() -> Vec<Value> {
    let path = todos_file_path();
    let Ok(data) = fs::read(path) else { return Vec::new() };
    let parsed = serde_json::from_slice::<Vec<Value>>(&data).unwrap_or_default();
    canonicalized_todos(parsed, "agent")
}

fn write_json_array(items: Vec<Value>) -> Result<(), String> {
    let path = todos_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let canonical = canonicalized_todos(items, "agent");
    let data = serde_json::to_vec_pretty(&canonical).map_err(|error| error.to_string())?;
    fs::write(path, data).map_err(|error| error.to_string())
}

fn canonicalized_todos(items: Vec<Value>, default_source: &str) -> Vec<Value> {
    let mut by_id: BTreeMap<String, Value> = BTreeMap::new();
    let mut id_order: Vec<String> = Vec::new();
    let mut legacy_title_index: BTreeMap<String, String> = BTreeMap::new();

    for raw in items {
        let has_provided_id = provided_todo_id(&raw).is_some();
        let Some(mut item) = canonical_todo(&raw, default_source) else { continue };
        let id = string_field(&item, "id")
            .map(ToString::to_string)
            .unwrap_or_else(new_id);
        item["id"] = Value::String(id.clone());
        let title = string_field(&item, "title")
            .unwrap_or_default()
            .trim()
            .to_lowercase();

        let existing_id = if by_id.contains_key(&id) {
            Some(id.clone())
        } else if !has_provided_id {
            legacy_title_index.get(&title).cloned()
        } else {
            None
        };

        if let Some(existing_id) = existing_id {
            if let Some(existing) = by_id.get(&existing_id).cloned() {
                let merged = merge_todo_fields(existing, item);
                by_id.insert(existing_id, merged);
                continue;
            }
        }

        by_id.insert(id.clone(), item);
        id_order.push(id.clone());
        if !has_provided_id {
            legacy_title_index.insert(title, id);
        }
    }

    id_order
        .into_iter()
        .filter_map(|id| by_id.remove(&id))
        .collect()
}

fn canonical_todo(raw: &Value, default_source: &str) -> Option<Value> {
    let object = raw.as_object()?;
    let title = object
        .get("title")
        .and_then(Value::as_str)
        .or_else(|| object.get("content").and_then(Value::as_str))
        .unwrap_or_default()
        .trim()
        .to_string();
    if title.is_empty() {
        return None;
    }

    let now = iso_now();
    let id = object
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(new_id);
    let created_at = normalize_timestamp(object.get("createdAt").and_then(Value::as_str))
        .unwrap_or_else(|| now.clone());
    let updated_at = normalize_timestamp(object.get("updatedAt").and_then(Value::as_str))
        .unwrap_or_else(|| now.clone());
    let source = object
        .get("source")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(default_source)
        .to_string();
    let linked_files = object
        .get("linkedFiles")
        .or_else(|| object.get("files"))
        .and_then(Value::as_array)
        .map(|items| {
            let mut files = items
                .iter()
                .filter_map(Value::as_str)
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>();
            files.sort();
            files.dedup();
            files
        })
        .unwrap_or_default();

    let mut todo = json!({
        "id": id,
        "title": title,
        "status": normalize_status(object.get("status").and_then(Value::as_str).unwrap_or_default()),
        "priority": normalize_priority(object.get("priority").and_then(Value::as_str).unwrap_or_default()),
        "source": source,
        "createdAt": created_at,
        "updatedAt": updated_at,
        "notes": object.get("notes").and_then(Value::as_str).unwrap_or_default().trim(),
        "activeForm": object.get("activeForm").and_then(Value::as_str).unwrap_or_default().trim(),
        "linkedFiles": linked_files,
        "isPlanCanonical": object.get("isPlanCanonical").and_then(Value::as_bool).unwrap_or(false),
    });
    if let Some(plan_conversation_id) = object
        .get("planConversationId")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        todo["planConversationId"] = Value::String(plan_conversation_id.to_string());
    }
    Some(todo)
}

fn merge_todo_fields(mut target: Value, incoming: Value) -> Value {
    if let Some(status) = string_field(&incoming, "status") {
        target["status"] = Value::String(normalize_status(status));
    }
    if let Some(priority) = string_field(&incoming, "priority") {
        target["priority"] = Value::String(normalize_priority(priority));
    }
    if let Some(notes) = string_field(&incoming, "notes") {
        target["notes"] = Value::String(notes.to_string());
    }
    if let Some(active_form) = string_field(&incoming, "activeForm") {
        target["activeForm"] = Value::String(active_form.to_string());
    }
    if let Some(files) = incoming.get("linkedFiles").and_then(Value::as_array) {
        target["linkedFiles"] = Value::Array(files.clone());
    }
    if let Some(source) = string_field(&incoming, "source") {
        if !source.is_empty() {
            target["source"] = Value::String(source.to_string());
        }
    }
    if let Some(plan_conversation_id) = string_field(&incoming, "planConversationId") {
        target["planConversationId"] = Value::String(plan_conversation_id.to_string());
    }
    if let Some(created_at) = string_field(&incoming, "createdAt") {
        target["createdAt"] = Value::String(
            normalize_timestamp(Some(created_at))
                .unwrap_or_else(|| created_at.to_string()),
        );
    } else if target.get("createdAt").is_none() {
        target["createdAt"] = Value::String(iso_now());
    }
    target["updatedAt"] = Value::String(
        normalize_timestamp(string_field(&incoming, "updatedAt"))
            .unwrap_or_else(iso_now),
    );
    target
}

fn provided_todo_id(raw: &Value) -> Option<String> {
    raw.get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn parse_string_array(raw: Option<&str>) -> Option<Vec<String>> {
    raw.and_then(|text| {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return Some(Vec::new());
        }
        let parsed = serde_json::from_str::<Value>(trimmed).ok()?;
        parsed.as_array().map(|items| {
            items.iter()
                .filter_map(Value::as_str)
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>()
        })
    })
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

fn normalize_status(raw: &str) -> String {
    let normalized = raw
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .replace(' ', "_");
    match normalized.as_str() {
        "pending" | "in_progress" | "done" | "blocked" => normalized,
        "completed" | "complete" | "finished" => "done".to_string(),
        "running" | "active" | "doing" | "started" => "in_progress".to_string(),
        "todo" | "open" | "queued" | "waiting" => "pending".to_string(),
        "failed" | "error" | "stuck" | "cancelled" | "canceled" | "aborted" | "skipped" => {
            "blocked".to_string()
        }
        _ => "pending".to_string(),
    }
}

fn normalize_priority(raw: &str) -> String {
    match raw.trim().to_lowercase().as_str() {
        "low" => "low".to_string(),
        "high" => "high".to_string(),
        _ => "medium".to_string(),
    }
}

fn normalize_timestamp(raw: Option<&str>) -> Option<String> {
    let value = raw?.trim();
    if value.is_empty() {
        None
    } else {
        Some(value.to_string())
    }
}

fn string_field<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn string_arg(arguments: &BTreeMap<String, String>, key: &str) -> String {
    arguments
        .get(key)
        .map(String::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn new_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("todo-{nanos}")
}

fn iso_now() -> String {
    new_id()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, OnceLock};

    fn env_lock() -> &'static Mutex<()> {
        static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        LOCK.get_or_init(|| Mutex::new(()))
    }

    fn with_temp_home<T>(test: impl FnOnce() -> T) -> T {
        let _guard = env_lock().lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let original = std::env::var("HOME").ok();
        let temp_home = std::env::temp_dir().join(format!("todo-state-home-{}", new_id()));
        std::fs::create_dir_all(&temp_home).unwrap();
        std::env::set_var("HOME", &temp_home);
        let result = test();
        if let Some(original) = original {
            std::env::set_var("HOME", original);
        } else {
            std::env::remove_var("HOME");
        }
        let _ = std::fs::remove_dir_all(temp_home);
        result
    }

    #[test]
    fn canonicalization_keeps_different_explicit_ids() {
        with_temp_home(|| {
            write_json_array(vec![
                json!({"id":"todo-explicit-a","title":"Allineare KPI baseline","status":"pending"}),
                json!({"id":"todo-explicit-b","title":"Allineare KPI baseline","status":"done"}),
            ])
            .unwrap();
            let todos = read_todos();
            let matching = todos
                .into_iter()
                .filter(|todo| string_field(todo, "title") == Some("Allineare KPI baseline"))
                .collect::<Vec<_>>();
            assert_eq!(matching.len(), 2);
        });
    }

    #[test]
    fn canonicalization_merges_missing_ids_by_title() {
        with_temp_home(|| {
            write_json_array(vec![
                json!({"title":"Definire baseline tecnica","status":"pending"}),
                json!({"title":"Definire baseline tecnica","status":"done"}),
            ])
            .unwrap();
            let todos = read_todos();
            let matching = todos
                .into_iter()
                .filter(|todo| string_field(todo, "title") == Some("Definire baseline tecnica"))
                .collect::<Vec<_>>();
            assert_eq!(matching.len(), 1);
            assert_eq!(string_field(&matching[0], "status"), Some("done"));
        });
    }

    #[test]
    fn canonicalization_does_not_merge_explicit_and_legacy_title() {
        with_temp_home(|| {
            write_json_array(vec![
                json!({"id":"todo-explicit-keep","title":"Stabilizzare debug session","status":"in_progress"}),
                json!({"title":"Stabilizzare debug session","status":"done"}),
            ])
            .unwrap();
            let todos = read_todos();
            let matching = todos
                .into_iter()
                .filter(|todo| string_field(todo, "title") == Some("Stabilizzare debug session"))
                .collect::<Vec<_>>();
            assert_eq!(matching.len(), 2);
        });
    }
}
