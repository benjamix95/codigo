use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct PlanDocument {
    pub version: i32,
    pub latest_conversation_id: Option<String>,
    pub snapshots_by_conversation: BTreeMap<String, Vec<PlanSnapshot>>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PlanSnapshot {
    pub snapshot_id: String,
    pub conversation_id: String,
    pub goal: String,
    pub chosen_path: Option<String>,
    pub steps: Vec<PlanStep>,
    pub walkthrough_markdown: Option<String>,
    pub summary: Option<String>,
    pub outcome: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PlanStep {
    pub id: String,
    pub title: String,
    pub description: String,
    pub target_file: Option<String>,
    pub status: String,
    pub linked_files: Vec<String>,
    pub depends_on: Vec<String>,
    pub notes: String,
    pub updated_at: String,
}

pub fn create_snapshot(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let goal = string_arg(arguments, "goal");
    if goal.is_empty() {
        return Err("Error: 'goal' parameter is required".to_string());
    }
    let conversation_id = required_conversation_id(arguments)?;
    let steps = parse_steps(arguments.get("steps"))?;
    let chosen_path = non_empty(string_arg(arguments, "chosen_path"))
        .or_else(|| non_empty(string_arg(arguments, "chosenPath")));
    let mut document = read_document();
    let now = iso_now();
    let snapshot = PlanSnapshot {
        snapshot_id: next_id("snapshot"),
        conversation_id: conversation_id.clone(),
        goal,
        chosen_path,
        steps,
        walkthrough_markdown: None,
        summary: None,
        outcome: None,
        created_at: now.clone(),
        updated_at: now,
    };
    document.latest_conversation_id = Some(conversation_id.clone());
    document
        .snapshots_by_conversation
        .entry(conversation_id)
        .or_default()
        .push(snapshot);
    write_document(&document)?;
    Ok("OK — plan snapshot created".to_string())
}

pub fn read_latest(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let document = read_document();
    let Some(conversation_id) = resolve_conversation_id(arguments, &document) else {
        return Ok("No plan snapshots found.".to_string());
    };
    let include_history = bool_arg(arguments, "include_history").or_else(|| bool_arg(arguments, "includeHistory")).unwrap_or(false);
    let history_limit = int_arg(arguments, "history_limit")
        .or_else(|| int_arg(arguments, "historyLimit"))
        .unwrap_or(10)
        .clamp(1, 50) as usize;
    let Some(history) = document.snapshots_by_conversation.get(&conversation_id) else {
        return Ok("No plan snapshots found.".to_string());
    };
    let Some(latest) = history.last() else {
        return Ok("No plan snapshots found.".to_string());
    };
    let payload = json!({
        "version": document.version,
        "latest_conversation_id": document.latest_conversation_id,
        "conversation_id": conversation_id,
        "snapshot": latest,
        "history": if include_history {
            Value::Array(history.iter().rev().take(history_limit).rev().map(|snapshot| serde_json::to_value(snapshot).unwrap_or(Value::Null)).collect())
        } else {
            Value::Null
        }
    });
    Ok(pretty_json(payload))
}

pub fn read_history(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let document = read_document();
    let Some(conversation_id) = resolve_conversation_id(arguments, &document) else {
        return Ok("[]".to_string());
    };
    let limit = int_arg(arguments, "limit").unwrap_or(10).clamp(1, 50) as usize;
    let history = document
        .snapshots_by_conversation
        .get(&conversation_id)
        .cloned()
        .unwrap_or_default();
    let recent = history.into_iter().rev().take(limit).collect::<Vec<_>>();
    Ok(pretty_json(json!(recent.into_iter().rev().collect::<Vec<_>>())))
}

pub fn step_update(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let step_id = required_string(arguments, "step_id")?;
    let status = normalize_status(&required_string(arguments, "status")?);
    let conversation_id = required_conversation_id(arguments)?;
    mutate_latest_snapshot(&conversation_id, |snapshot| {
        upsert_step(snapshot, &step_id, &status, None, None, None, None, None, None);
    })?;
    Ok(format!("OK — plan step {step_id} updated to {status}"))
}

pub fn step_upsert(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let step_id = required_string(arguments, "step_id").or_else(|_| required_string(arguments, "stepId"))?;
    let status = normalize_status(&required_string(arguments, "status")?);
    let conversation_id = required_conversation_id(arguments)?;
    mutate_latest_snapshot(&conversation_id, |snapshot| {
        upsert_step(
            snapshot,
            &step_id,
            &status,
            non_empty(string_arg(arguments, "title")),
            non_empty(string_arg(arguments, "description")),
            non_empty(string_arg(arguments, "target_file")).or_else(|| non_empty(string_arg(arguments, "targetFile"))),
            parse_string_array(arguments.get("linked_files")).or_else(|| parse_string_array(arguments.get("linkedFiles"))),
            parse_string_array(arguments.get("depends_on")).or_else(|| parse_string_array(arguments.get("dependsOn"))),
            non_empty(string_arg(arguments, "notes")),
        );
    })?;
    Ok(format!("OK — plan step {step_id} upserted"))
}

pub fn diff(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    let from_snapshot_id = required_string(arguments, "from_snapshot_id")
        .or_else(|_| required_string(arguments, "fromSnapshotId"))?;
    let document = read_document();
    let snapshots = document
        .snapshots_by_conversation
        .values()
        .flat_map(|items| items.iter())
        .collect::<Vec<_>>();
    let Some(from) = snapshots.iter().find(|snapshot| snapshot.snapshot_id == from_snapshot_id) else {
        return Err(format!("Error: unable to compute plan diff for from_snapshot_id '{from_snapshot_id}'"));
    };
    let to_snapshot_id = non_empty(string_arg(arguments, "to_snapshot_id"))
        .or_else(|| non_empty(string_arg(arguments, "toSnapshotId")));
    let to = if let Some(to_snapshot_id) = to_snapshot_id {
        snapshots
            .iter()
            .copied()
            .find(|snapshot| snapshot.snapshot_id == to_snapshot_id)
    } else {
        document
            .snapshots_by_conversation
            .get(&from.conversation_id)
            .and_then(|history| history.last())
    };
    let Some(to) = to else {
        return Err(format!("Error: unable to compute plan diff for from_snapshot_id '{from_snapshot_id}'"));
    };
    let added = to.steps.iter().filter(|step| !from.steps.iter().any(|prev| prev.id == step.id)).cloned().collect::<Vec<_>>();
    let removed = from.steps.iter().filter(|step| !to.steps.iter().any(|next| next.id == step.id)).cloned().collect::<Vec<_>>();
    let status_changes = to.steps.iter().filter_map(|step| {
        from.steps.iter().find(|prev| prev.id == step.id && prev.status != step.status).map(|prev| {
            json!({
                "step_id": step.id,
                "title": step.title,
                "from_status": prev.status,
                "to_status": step.status
            })
        })
    }).collect::<Vec<_>>();
    Ok(pretty_json(json!({
        "from_snapshot_id": from.snapshot_id,
        "to_snapshot_id": to.snapshot_id,
        "goal_changed": from.goal != to.goal,
        "added_steps": added,
        "removed_steps": removed,
        "status_changes": status_changes
    })))
}

fn mutate_latest_snapshot<F>(conversation_id: &str, mutate: F) -> Result<(), String>
where
    F: FnOnce(&mut PlanSnapshot),
{
    let mut document = read_document();
    let history = document
        .snapshots_by_conversation
        .get_mut(conversation_id)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let snapshot = history
        .last_mut()
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    mutate(snapshot);
    snapshot.updated_at = iso_now();
    write_document(&document)
}

fn upsert_step(snapshot: &mut PlanSnapshot, step_id: &str, status: &str, title: Option<String>, description: Option<String>, target_file: Option<String>, linked_files: Option<Vec<String>>, depends_on: Option<Vec<String>>, notes: Option<String>) {
    if let Some(step) = snapshot.steps.iter_mut().find(|step| step.id == step_id) {
        step.status = status.to_string();
        if let Some(title) = title { step.title = title; }
        if let Some(description) = description { step.description = description; }
        if let Some(target_file) = target_file { step.target_file = Some(target_file); }
        if let Some(linked_files) = linked_files { step.linked_files = linked_files; }
        if let Some(depends_on) = depends_on { step.depends_on = depends_on; }
        if let Some(notes) = notes { step.notes = notes; }
        step.updated_at = iso_now();
        return;
    }
    let resolved_title = title.clone().unwrap_or_else(|| format!("Step {step_id}"));
    snapshot.steps.push(PlanStep {
        id: step_id.to_string(),
        title: resolved_title.clone(),
        description: description.unwrap_or(resolved_title),
        target_file,
        status: status.to_string(),
        linked_files: linked_files.unwrap_or_default(),
        depends_on: depends_on.unwrap_or_default(),
        notes: notes.unwrap_or_default(),
        updated_at: iso_now(),
    });
}

fn parse_steps(value: Option<&Value>) -> Result<Vec<PlanStep>, String> {
    let Some(value) = value else { return Ok(Vec::new()) };
    let normalized = if let Some(text) = value.as_str() {
        serde_json::from_str::<Value>(text).map_err(|_| "Error: 'steps' must be a valid JSON array".to_string())?
    } else {
        value.clone()
    };
    let Some(items) = normalized.as_array() else {
        return Err("Error: 'steps' must be a valid JSON array".to_string());
    };
    Ok(items.iter().enumerate().map(|(index, item)| PlanStep {
        id: string_field(item, "id").unwrap_or_else(|| format!("{}", index + 1)),
        title: string_field(item, "title").unwrap_or_else(|| format!("Step {}", index + 1)),
        description: string_field(item, "description").unwrap_or_else(|| string_field(item, "title").unwrap_or_else(|| format!("Step {}", index + 1))),
        target_file: optional_field(item, "target_file").or_else(|| optional_field(item, "targetFile")),
        status: normalize_status(&string_field(item, "status").unwrap_or_else(|| "pending".to_string())),
        linked_files: item.get("linked_files").and_then(Value::as_array).map(|entries| entries.iter().filter_map(|entry| entry.as_str().map(ToString::to_string)).collect()).unwrap_or_default(),
        depends_on: item.get("depends_on").and_then(Value::as_array).map(|entries| entries.iter().filter_map(|entry| entry.as_str().map(ToString::to_string)).collect()).unwrap_or_default(),
        notes: string_field(item, "notes").unwrap_or_default(),
        updated_at: iso_now(),
    }).collect())
}

fn parse_string_array(value: Option<&Value>) -> Option<Vec<String>> {
    value.and_then(|value| value.as_array().map(|items| items.iter().filter_map(|item| item.as_str().map(ToString::to_string)).collect::<Vec<_>>()))
}

fn required_conversation_id(arguments: &BTreeMap<String, Value>) -> Result<String, String> {
    required_string(arguments, "conversation_id").or_else(|_| required_string(arguments, "conversationId"))
}

fn required_string(arguments: &BTreeMap<String, Value>, key: &str) -> Result<String, String> {
    non_empty(string_arg(arguments, key)).ok_or_else(|| format!("Error: '{key}' is required"))
}

fn resolve_conversation_id(arguments: &BTreeMap<String, Value>, document: &PlanDocument) -> Option<String> {
    non_empty(string_arg(arguments, "conversation_id"))
        .or_else(|| non_empty(string_arg(arguments, "conversationId")))
        .or_else(|| document.latest_conversation_id.clone())
        .or_else(|| document.snapshots_by_conversation.keys().last().cloned())
}

fn read_document() -> PlanDocument {
    let path = plan_state_file_path();
    let Ok(data) = fs::read(path) else { return PlanDocument { version: 1, ..PlanDocument::default() } };
    serde_json::from_slice(&data).unwrap_or(PlanDocument { version: 1, ..PlanDocument::default() })
}

fn write_document(document: &PlanDocument) -> Result<(), String> {
    let path = plan_state_file_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(document).map_err(|error| error.to_string())?;
    fs::write(path, data).map_err(|error| error.to_string())
}

fn plan_state_file_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared")
        .join("plan_state.json")
}

fn iso_now() -> String {
    next_id("ts")
}

fn next_id(prefix: &str) -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
    format!("{prefix}-{nanos}")
}

fn pretty_json(value: Value) -> String {
    serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string())
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments.get(key).and_then(Value::as_str).unwrap_or_default().trim().to_string()
}

fn string_field(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(|text| text.trim().to_string()).filter(|text| !text.is_empty())
}

fn optional_field(value: &Value, key: &str) -> Option<String> {
    string_field(value, key)
}

fn normalize_status(raw: &str) -> String {
    match raw.trim().to_lowercase().as_str() {
        "running" | "in_progress" | "active" | "started" => "running".to_string(),
        "done" | "completed" | "complete" | "finished" | "success" => "done".to_string(),
        "failed" | "error" | "blocked" | "stuck" | "cancelled" | "canceled" | "aborted" | "skipped" => "failed".to_string(),
        _ => "pending".to_string(),
    }
}

fn non_empty(value: String) -> Option<String> {
    if value.is_empty() { None } else { Some(value) }
}

fn int_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    arguments.get(key).and_then(Value::as_i64)
}

fn bool_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<bool> {
    arguments.get(key).and_then(Value::as_bool)
}
