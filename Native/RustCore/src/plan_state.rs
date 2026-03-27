use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanDocument {
    pub version: i32,
    pub latest_conversation_id: Option<String>,
    pub snapshots_by_conversation: BTreeMap<String, Vec<PlanSnapshot>>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
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
#[serde(rename_all = "camelCase")]
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

pub fn handle_action(action: &str, arguments: &BTreeMap<String, String>) -> Result<String, String> {
    match action {
        "plan_create" => create_snapshot(arguments),
        "plan_read" => read_latest(arguments),
        "plan_history_read" => read_history(arguments),
        "plan_step_update" => step_update(arguments),
        "plan_step_upsert" => step_upsert(arguments),
        "plan_step_batch_update" => step_batch_update(arguments),
        "plan_step_reorder" => step_reorder(arguments),
        "plan_step_dependency_set" => step_dependency_set(arguments),
        "plan_set_walkthrough" => set_walkthrough(arguments),
        "plan_diff" => diff(arguments),
        "plan_request_user_input" => request_user_input(arguments),
        _ => Err(format!("Error: unsupported plan action '{action}'")),
    }
}

pub fn create_snapshot(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let goal = required_string(arguments, "goal")?;
    let chosen_path = non_empty(string_arg(arguments, "chosen_path"))
        .or_else(|| non_empty(string_arg(arguments, "chosenPath")));
    let steps = parse_steps(string_arg(arguments, "steps").as_str())?;
    let replace_existing = bool_arg(arguments, "replace_existing")
        .or_else(|| bool_arg(arguments, "replaceExisting"))
        .unwrap_or(true);

    let mut document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let history = document
        .snapshots_by_conversation
        .entry(conversation_id.clone())
        .or_default();

    let now = iso_now();
    let next_snapshot = if !replace_existing {
        if let Some(previous) = history.last().cloned() {
            let existing_ids = previous
                .steps
                .iter()
                .map(|step| step.id.clone())
                .collect::<BTreeSet<_>>();
            let filtered = steps
                .into_iter()
                .filter(|step| !existing_ids.contains(&step.id))
                .collect::<Vec<_>>();
            let added_count = filtered.len();
            let mut merged_steps = previous.steps.clone();
            merged_steps.extend(filtered);
            let updated = PlanSnapshot {
                snapshot_id: next_id("snapshot"),
                conversation_id: conversation_id.clone(),
                goal: goal.clone(),
                chosen_path,
                steps: merged_steps,
                walkthrough_markdown: previous.walkthrough_markdown.clone(),
                summary: previous.summary.clone(),
                outcome: previous.outcome.clone(),
                created_at: now.clone(),
                updated_at: now,
            };
            history.push(updated);
            document.latest_conversation_id = Some(conversation_id);
            write_document(&document)?;
            return Ok(format!(
                "OK — plan snapshot updated ({added_count} new step(s) merged)"
            ));
        }
        PlanSnapshot {
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
        }
    } else {
        PlanSnapshot {
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
        }
    };

    history.push(next_snapshot);
    document.latest_conversation_id = Some(conversation_id);
    write_document(&document)?;
    Ok("OK — plan snapshot created".to_string())
}

pub fn read_latest(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let document = read_document();
    let Some(conversation_id) = resolve_conversation_id(arguments, &document) else {
        return Ok("No plan snapshots found.".to_string());
    };
    let include_history = bool_arg(arguments, "include_history")
        .or_else(|| bool_arg(arguments, "includeHistory"))
        .unwrap_or(false);
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
            Value::Array(
                history.iter()
                    .rev()
                    .take(history_limit)
                    .rev()
                    .map(|snapshot| serde_json::to_value(snapshot).unwrap_or(Value::Null))
                    .collect()
            )
        } else {
            Value::Null
        }
    });
    Ok(pretty_json(payload))
}

pub fn read_history(arguments: &BTreeMap<String, String>) -> Result<String, String> {
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
    Ok(pretty_json(json!(recent
        .into_iter()
        .rev()
        .collect::<Vec<_>>())))
}

pub fn step_update(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let step_id =
        required_string(arguments, "step_id").or_else(|_| required_string(arguments, "stepId"))?;
    let status = required_string(arguments, "status")?;
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let title = non_empty(string_arg(arguments, "title"));
    mutate_latest_snapshot(&conversation_id, true, |snapshot| {
        upsert_step(
            snapshot, &step_id, &status, title, None, None, None, None, None,
        );
    })?;
    Ok(format!("OK — plan step {step_id} updated to {status}"))
}

pub fn step_upsert(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let step_id =
        required_string(arguments, "step_id").or_else(|_| required_string(arguments, "stepId"))?;
    let status = required_string(arguments, "status")?;
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let linked_files = optional_string_array_from_args(arguments, "linked_files", "linkedFiles")?;
    let depends_on_args = optional_string_array_from_args(arguments, "depends_on", "dependsOn")?;
    mutate_latest_snapshot(&conversation_id, true, |snapshot| {
        upsert_step(
            snapshot,
            &step_id,
            &status,
            non_empty(string_arg(arguments, "title")),
            non_empty(string_arg(arguments, "description")),
            non_empty(string_arg(arguments, "target_file"))
                .or_else(|| non_empty(string_arg(arguments, "targetFile"))),
            linked_files,
            depends_on_args,
            non_empty(string_arg(arguments, "notes")),
        );
    })?;
    Ok(format!("OK — plan step {step_id} upserted"))
}

pub fn step_batch_update(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let updates = parse_value_array(arguments.get("updates").map(String::as_str), "updates")?;
    if updates.is_empty() {
        return Err("Error: 'updates' must be a non-empty JSON array".to_string());
    }
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let mut batch_linked: Vec<Option<Vec<String>>> = Vec::with_capacity(updates.len());
    let mut batch_depends: Vec<Option<Vec<String>>> = Vec::with_capacity(updates.len());
    for update in &updates {
        batch_linked.push(parse_value_string_array_dual(
            update,
            "linkedFiles",
            "linked_files",
        )?);
        batch_depends.push(parse_value_string_array_dual(
            update,
            "dependsOn",
            "depends_on",
        )?);
    }
    mutate_latest_snapshot(&conversation_id, true, |snapshot| {
        for (i, update) in updates.iter().enumerate() {
            let step_id = string_value(update, "stepId")
                .or_else(|| string_value(update, "step_id"))
                .unwrap_or_default();
            let status = string_value(update, "status").unwrap_or_else(|| "pending".to_string());
            upsert_step(
                snapshot,
                &step_id,
                &status,
                string_value(update, "title"),
                string_value(update, "description"),
                string_value(update, "targetFile").or_else(|| string_value(update, "target_file")),
                batch_linked[i].clone(),
                batch_depends[i].clone(),
                string_value(update, "notes"),
            );
        }
    })?;
    Ok(format!(
        "OK — batch plan update applied ({} steps)",
        updates.len()
    ))
}

pub fn step_reorder(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let ordered = optional_string_array_from_args(arguments, "ordered_step_ids", "orderedStepIds")?
        .ok_or_else(|| "Error: 'ordered_step_ids' must be a non-empty JSON array".to_string())?;
    if ordered.is_empty() {
        return Err("Error: 'ordered_step_ids' must contain at least one id".to_string());
    }
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, false)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    mutate_latest_snapshot(&conversation_id, false, |snapshot| {
        let mut reordered = Vec::new();
        let mut used = BTreeSet::new();
        for step_id in &ordered {
            if let Some(existing) = snapshot.steps.iter().find(|step| &step.id == step_id) {
                reordered.push(existing.clone());
            } else {
                reordered.push(PlanStep {
                    id: step_id.clone(),
                    title: format!("Step {step_id}"),
                    description: format!("Step {step_id}"),
                    target_file: None,
                    status: "pending".to_string(),
                    linked_files: Vec::new(),
                    depends_on: Vec::new(),
                    notes: String::new(),
                    updated_at: iso_now(),
                });
            }
            used.insert(step_id.clone());
        }
        reordered.extend(
            snapshot
                .steps
                .iter()
                .filter(|step| !used.contains(&step.id))
                .cloned(),
        );
        snapshot.steps = reordered;
    })?;
    Ok("OK — plan step order updated".to_string())
}

pub fn step_dependency_set(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let step_id =
        required_string(arguments, "step_id").or_else(|_| required_string(arguments, "stepId"))?;
    let depends_on = optional_string_array_from_args(arguments, "depends_on", "dependsOn")?
        .ok_or_else(|| "Error: 'depends_on' must be a valid JSON string array".to_string())?;
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    mutate_latest_snapshot(&conversation_id, true, |snapshot| {
        let existing_status = snapshot
            .steps
            .iter()
            .find(|step| step.id == step_id)
            .map(|step| step.status.clone())
            .unwrap_or_else(|| "pending".to_string());
        upsert_step(
            snapshot,
            &step_id,
            &existing_status,
            None,
            None,
            None,
            None,
            Some(depends_on),
            None,
        );
    })?;
    Ok(format!("OK — dependencies set for step {step_id}"))
}

pub fn set_walkthrough(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let markdown = required_string(arguments, "markdown")?;
    let document = read_document();
    let conversation_id = resolve_mutation_conversation_id(arguments, &document, true)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    mutate_latest_snapshot(&conversation_id, true, |snapshot| {
        snapshot.walkthrough_markdown = Some(markdown);
        snapshot.summary = non_empty(string_arg(arguments, "summary"));
        snapshot.outcome = Some(parse_outcome(&string_arg(arguments, "outcome")));
    })?;
    Ok("OK — walkthrough stored".to_string())
}

pub fn request_user_input(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let questions = parse_value_array(arguments.get("questions").map(String::as_str), "questions")?;
    if questions.is_empty() {
        return Err("Error: 'questions' must be a non-empty JSON array".to_string());
    }
    if questions.len() > 6 {
        return Err("Error: 'questions' supports up to 6 items per call".to_string());
    }
    for (index, question) in questions.iter().enumerate() {
        let prompt = string_value(question, "prompt")
            .or_else(|| string_value(question, "question"))
            .or_else(|| string_value(question, "title"))
            .unwrap_or_default();
        if prompt.is_empty() {
            return Err(format!(
                "Error: questions[{index}] requires a non-empty 'prompt' (or 'question')"
            ));
        }
        let options = question
            .get("options")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| {
                        item.as_str()
                            .map(ToString::to_string)
                            .or_else(|| string_value(item, "label"))
                            .or_else(|| string_value(item, "text"))
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        if options.len() < 2 {
            return Err(format!(
                "Error: questions[{index}] must provide at least 2 options"
            ));
        }
        if options.len() > 5 {
            return Err(format!(
                "Error: questions[{index}] supports at most 5 options"
            ));
        }
    }

    let title = non_empty(string_arg(arguments, "title"))
        .unwrap_or_else(|| "Clarification questions".to_string());
    let phase =
        non_empty(string_arg(arguments, "phase")).unwrap_or_else(|| "questioning".to_string());
    let round = non_empty(string_arg(arguments, "round")).unwrap_or_else(|| "n/a".to_string());
    let context = non_empty(string_arg(arguments, "context"))
        .map(|value| format!(" | context: {value}"))
        .unwrap_or_default();
    let conversation = non_empty(string_arg(arguments, "conversation_id"))
        .or_else(|| non_empty(string_arg(arguments, "conversationId")))
        .map(|value| format!(" | conversation_id: {value}"))
        .unwrap_or_default();

    Ok(format!(
        "OK — queued {} clarification question(s) [title: {} | phase: {} | round: {}]{}{}",
        questions.len(),
        title,
        phase,
        round,
        conversation,
        context
    ))
}

pub fn diff(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    let from_snapshot_id = required_string(arguments, "from_snapshot_id")
        .or_else(|_| required_string(arguments, "fromSnapshotId"))?;
    let to_snapshot_id = non_empty(string_arg(arguments, "to_snapshot_id"))
        .or_else(|| non_empty(string_arg(arguments, "toSnapshotId")));
    let document = read_document();
    let snapshots = document
        .snapshots_by_conversation
        .values()
        .flat_map(|items| items.iter())
        .collect::<Vec<_>>();
    let Some(from) = snapshots
        .iter()
        .copied()
        .find(|snapshot| snapshot.snapshot_id == from_snapshot_id)
    else {
        return diff_error(&from_snapshot_id, to_snapshot_id.as_deref());
    };
    let to = if let Some(to_snapshot_id) = to_snapshot_id.as_ref() {
        snapshots
            .iter()
            .copied()
            .find(|snapshot| snapshot.snapshot_id == *to_snapshot_id)
    } else {
        document
            .snapshots_by_conversation
            .get(&from.conversation_id)
            .and_then(|history| history.last())
    };
    let Some(to) = to else {
        return diff_error(&from_snapshot_id, to_snapshot_id.as_deref());
    };

    let added = to
        .steps
        .iter()
        .filter(|step| !from.steps.iter().any(|prev| prev.id == step.id))
        .cloned()
        .collect::<Vec<_>>();
    let removed = from
        .steps
        .iter()
        .filter(|step| !to.steps.iter().any(|next| next.id == step.id))
        .cloned()
        .collect::<Vec<_>>();
    let status_changes = to
        .steps
        .iter()
        .filter_map(|step| {
            from.steps
                .iter()
                .find(|prev| prev.id == step.id && prev.status != step.status)
                .map(|prev| {
                    json!({
                        "stepId": step.id,
                        "title": step.title,
                        "fromStatus": prev.status,
                        "toStatus": step.status
                    })
                })
        })
        .collect::<Vec<_>>();
    Ok(pretty_json(json!({
        "from_snapshot_id": from.snapshot_id,
        "to_snapshot_id": to.snapshot_id,
        "goal_changed": from.goal != to.goal,
        "added_steps": added,
        "removed_steps": removed,
        "status_changes": status_changes
    })))
}

fn diff_error(from_snapshot_id: &str, to_snapshot_id: Option<&str>) -> Result<String, String> {
    let target_suffix = to_snapshot_id
        .map(|value| format!(" and to_snapshot_id '{value}'"))
        .unwrap_or_default();
    Err(format!(
        "Error: unable to compute plan diff for from_snapshot_id '{from_snapshot_id}'{target_suffix}"
    ))
}

fn mutate_latest_snapshot<F>(
    conversation_id: &str,
    create_if_missing: bool,
    mutate: F,
) -> Result<(), String>
where
    F: FnOnce(&mut PlanSnapshot),
{
    let mut document = read_document();
    if create_if_missing
        && !document
            .snapshots_by_conversation
            .contains_key(conversation_id)
    {
        let now = iso_now();
        document.snapshots_by_conversation.insert(
            conversation_id.to_string(),
            vec![PlanSnapshot {
                snapshot_id: next_id("snapshot"),
                conversation_id: conversation_id.to_string(),
                goal: "Operational plan in progress".to_string(),
                chosen_path: None,
                steps: Vec::new(),
                walkthrough_markdown: None,
                summary: None,
                outcome: None,
                created_at: now.clone(),
                updated_at: now,
            }],
        );
        document.latest_conversation_id = Some(conversation_id.to_string());
    }
    let history = document
        .snapshots_by_conversation
        .get_mut(conversation_id)
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let base = history
        .last()
        .cloned()
        .ok_or_else(|| "Error: unable to resolve target plan snapshot".to_string())?;
    let now = iso_now();
    let mut next = PlanSnapshot {
        snapshot_id: next_id("snapshot"),
        conversation_id: base.conversation_id,
        goal: base.goal,
        chosen_path: base.chosen_path,
        steps: base.steps,
        walkthrough_markdown: base.walkthrough_markdown,
        summary: base.summary,
        outcome: base.outcome,
        created_at: now.clone(),
        updated_at: now,
    };
    mutate(&mut next);
    next.updated_at = iso_now();
    history.push(next);
    write_document(&document)
}

#[allow(clippy::too_many_arguments)]
fn upsert_step(
    snapshot: &mut PlanSnapshot,
    step_id: &str,
    status: &str,
    title: Option<String>,
    description: Option<String>,
    target_file: Option<String>,
    linked_files: Option<Vec<String>>,
    depends_on: Option<Vec<String>>,
    notes: Option<String>,
) {
    if let Some(step) = snapshot.steps.iter_mut().find(|step| step.id == step_id) {
        step.status = status.to_string();
        if let Some(title) = title {
            step.title = title;
        }
        if let Some(description) = description {
            step.description = description;
        }
        if let Some(target_file) = target_file {
            step.target_file = Some(target_file);
        }
        if let Some(linked_files) = linked_files {
            step.linked_files = linked_files;
        }
        if let Some(depends_on) = depends_on {
            step.depends_on = depends_on;
        }
        if let Some(notes) = notes {
            step.notes = notes;
        }
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

fn parse_steps(raw: &str) -> Result<Vec<PlanStep>, String> {
    if raw.trim().is_empty() {
        return Ok(Vec::new());
    }
    let parsed = serde_json::from_str::<Value>(raw)
        .map_err(|_| "Error: 'steps' must be a valid JSON array".to_string())?;
    let Some(items) = parsed.as_array() else {
        return Err("Error: 'steps' must be a valid JSON array".to_string());
    };
    let mut steps = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        let linked_files =
            parse_value_string_array_dual(item, "linked_files", "linkedFiles")?.unwrap_or_default();
        let depends_on =
            parse_value_string_array_dual(item, "depends_on", "dependsOn")?.unwrap_or_default();
        steps.push(PlanStep {
            id: string_value(item, "id")
                .or_else(|| string_value(item, "step_id"))
                .unwrap_or_else(|| format!("{}", index + 1)),
            title: string_value(item, "title").unwrap_or_else(|| format!("Step {}", index + 1)),
            description: string_value(item, "description")
                .or_else(|| string_value(item, "title"))
                .unwrap_or_else(|| format!("Step {}", index + 1)),
            target_file: string_value(item, "target_file")
                .or_else(|| string_value(item, "targetFile")),
            status: string_value(item, "status").unwrap_or_else(|| "pending".to_string()),
            linked_files,
            depends_on,
            notes: string_value(item, "notes").unwrap_or_default(),
            updated_at: iso_now(),
        });
    }
    Ok(steps)
}

fn non_empty_string_items(items: &[Value]) -> Vec<String> {
    items
        .iter()
        .filter_map(|item| item.as_str().map(|text| text.trim().to_string()))
        .filter(|text| !text.is_empty())
        .collect()
}

/// JSON array string (or absent). Malformed JSON → `Err`.
fn parse_string_array(raw: Option<&str>) -> Result<Option<Vec<String>>, String> {
    let Some(text) = raw else {
        return Ok(None);
    };
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Ok(Some(Vec::new()));
    }
    let parsed: Value = serde_json::from_str(trimmed)
        .map_err(|e| format!("Invalid JSON in array field (expected JSON array): {e}"))?;
    let Some(items) = parsed.as_array() else {
        return Err(
            "String value for array field must parse to a JSON array of strings.".to_string(),
        );
    };
    Ok(Some(non_empty_string_items(items)))
}

fn parse_value_string_array(value: Option<&Value>) -> Result<Option<Vec<String>>, String> {
    let Some(value) = value else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    if let Some(items) = value.as_array() {
        return Ok(Some(non_empty_string_items(items)));
    }
    if let Some(text) = value.as_str() {
        return parse_string_array(Some(text));
    }
    Ok(None)
}

fn parse_value_string_array_dual(
    item: &Value,
    primary_key: &str,
    secondary_key: &str,
) -> Result<Option<Vec<String>>, String> {
    let Some(obj) = item.as_object() else {
        return Ok(None);
    };
    let primary = obj.get(primary_key).filter(|v| !v.is_null());
    let secondary = obj.get(secondary_key).filter(|v| !v.is_null());
    match (primary, secondary) {
        (Some(v), _) => parse_value_string_array(Some(v)),
        (None, Some(v)) => parse_value_string_array(Some(v)),
        (None, None) => Ok(None),
    }
}

fn optional_string_array_from_args(
    arguments: &BTreeMap<String, String>,
    snake: &str,
    camel: &str,
) -> Result<Option<Vec<String>>, String> {
    let primary = non_empty(string_arg(arguments, snake));
    let secondary = non_empty(string_arg(arguments, camel));
    match (&primary, &secondary) {
        (Some(a), _) => parse_string_array(Some(a.as_str())),
        (None, Some(b)) => parse_string_array(Some(b.as_str())),
        (None, None) => Ok(None),
    }
}

fn parse_value_array(raw: Option<&str>, field_name: &str) -> Result<Vec<Value>, String> {
    let Some(raw) = raw else {
        return Err(format!(
            "Error: '{field_name}' must be a non-empty JSON array"
        ));
    };
    let parsed = serde_json::from_str::<Value>(raw)
        .map_err(|_| format!("Error: '{field_name}' must be a non-empty JSON array"))?;
    let Some(items) = parsed.as_array() else {
        return Err(format!(
            "Error: '{field_name}' must be a non-empty JSON array"
        ));
    };
    Ok(items.clone())
}

fn required_conversation_id(arguments: &BTreeMap<String, String>) -> Result<String, String> {
    required_string(arguments, "conversation_id")
        .or_else(|_| required_string(arguments, "conversationId"))
}

fn resolve_mutation_conversation_id(
    arguments: &BTreeMap<String, String>,
    document: &PlanDocument,
    create_if_missing: bool,
) -> Option<String> {
    if let Some(explicit) = non_empty(string_arg(arguments, "conversation_id"))
        .or_else(|| non_empty(string_arg(arguments, "conversationId")))
    {
        return Some(explicit);
    }

    if document.snapshots_by_conversation.len() == 1 {
        return document.snapshots_by_conversation.keys().next().cloned();
    }

    if document.snapshots_by_conversation.is_empty() && create_if_missing {
        return Some(generate_conversation_id());
    }

    None
}

fn required_string(arguments: &BTreeMap<String, String>, key: &str) -> Result<String, String> {
    non_empty(string_arg(arguments, key)).ok_or_else(|| format!("Error: '{key}' is required"))
}

fn resolve_conversation_id(
    arguments: &BTreeMap<String, String>,
    document: &PlanDocument,
) -> Option<String> {
    non_empty(string_arg(arguments, "conversation_id"))
        .or_else(|| non_empty(string_arg(arguments, "conversationId")))
        .or_else(|| document.latest_conversation_id.clone())
        .or_else(|| document.snapshots_by_conversation.keys().last().cloned())
}

fn read_document() -> PlanDocument {
    let path = plan_state_file_path();
    let Ok(data) = fs::read(path) else {
        return PlanDocument {
            version: 1,
            ..PlanDocument::default()
        };
    };
    serde_json::from_slice(&data).unwrap_or(PlanDocument {
        version: 1,
        ..PlanDocument::default()
    })
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

fn generate_conversation_id() -> String {
    static UUID_SEQUENCE: AtomicU64 = AtomicU64::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let sequence = UUID_SEQUENCE.fetch_add(1, Ordering::Relaxed) as u128;
    let mixed = nanos ^ sequence.rotate_left(17);
    let part1 = ((mixed >> 96) & 0xffff_ffff) as u32;
    let part2 = ((mixed >> 80) & 0xffff) as u16;
    let part3 = (((mixed >> 64) & 0x0fff) as u16) | 0x4000;
    let part4 = (((mixed >> 48) & 0x3fff) as u16) | 0x8000;
    let part5 = (mixed & 0x0000_ffff_ffff_ffff) as u64;
    format!("{part1:08x}-{part2:04x}-{part3:04x}-{part4:04x}-{part5:012x}")
}

fn next_id(prefix: &str) -> String {
    static SEQUENCE: AtomicU64 = AtomicU64::new(0);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{nanos}-{sequence}")
}

fn pretty_json(value: Value) -> String {
    serde_json::to_string_pretty(&value).unwrap_or_else(|_| "{}".to_string())
}

fn string_arg(arguments: &BTreeMap<String, String>, key: &str) -> String {
    arguments
        .get(key)
        .map(String::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn string_value(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
}

fn parse_outcome(raw: &str) -> String {
    match raw.trim().to_lowercase().as_str() {
        "failed" => "failed".to_string(),
        "cancelled" => "cancelled".to_string(),
        _ => "done".to_string(),
    }
}

fn non_empty(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn int_arg(arguments: &BTreeMap<String, String>, key: &str) -> Option<i64> {
    arguments
        .get(key)
        .and_then(|value| value.parse::<i64>().ok())
}

fn bool_arg(arguments: &BTreeMap<String, String>, key: &str) -> Option<bool> {
    arguments
        .get(key)
        .and_then(|value| match value.trim().to_lowercase().as_str() {
            "1" | "true" | "yes" | "y" => Some(true),
            "0" | "false" | "no" | "n" => Some(false),
            _ => None,
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn with_temp_home<T>(test: impl FnOnce() -> T) -> T {
        let _guard = crate::test_support::env_lock()
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        let original = std::env::var("HOME").ok();
        let temp_home = std::env::temp_dir().join(format!("plan-state-home-{}", next_id("test")));
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
    fn create_snapshot_merges_unique_steps_when_replace_existing_is_false() {
        with_temp_home(|| {
            let mut create_args = BTreeMap::new();
            create_args.insert("conversation_id".to_string(), "conv-1".to_string());
            create_args.insert("goal".to_string(), "Goal".to_string());
            create_args.insert(
                "steps".to_string(),
                r#"[{"step_id":"1","title":"Audit","status":"pending"}]"#.to_string(),
            );
            assert_eq!(
                create_snapshot(&create_args).unwrap(),
                "OK — plan snapshot created"
            );

            create_args.insert("replace_existing".to_string(), "false".to_string());
            create_args.insert(
                "steps".to_string(),
                r#"[{"step_id":"1","title":"Audit","status":"pending"},{"step_id":"2","title":"Patch","status":"pending"}]"#.to_string(),
            );
            let message = create_snapshot(&create_args).unwrap();
            assert_eq!(message, "OK — plan snapshot updated (1 new step(s) merged)");

            let history = read_document()
                .snapshots_by_conversation
                .get("conv-1")
                .cloned()
                .unwrap_or_default();
            let latest = history.last().unwrap();
            let step_ids = latest
                .steps
                .iter()
                .map(|step| step.id.as_str())
                .collect::<Vec<_>>();
            assert_eq!(step_ids, vec!["1", "2"]);
        });
    }

    #[test]
    fn step_upsert_rejects_malformed_linked_files_json() {
        with_temp_home(|| {
            let mut args = BTreeMap::new();
            args.insert("conversation_id".to_string(), "conv-bad-json".to_string());
            args.insert("step_id".to_string(), "1".to_string());
            args.insert("status".to_string(), "pending".to_string());
            args.insert("linked_files".to_string(), "[not json".to_string());
            let err = step_upsert(&args).unwrap_err();
            assert!(err.contains("Invalid JSON"), "unexpected error: {err}");
        });
    }

    #[test]
    fn step_upsert_creates_snapshot_when_missing() {
        with_temp_home(|| {
            let mut args = BTreeMap::new();
            args.insert("conversation_id".to_string(), "conv-2".to_string());
            args.insert("step_id".to_string(), "7".to_string());
            args.insert("status".to_string(), "running".to_string());
            args.insert("title".to_string(), "Plan".to_string());
            let message = step_upsert(&args).unwrap();
            assert_eq!(message, "OK — plan step 7 upserted");

            let latest = read_document()
                .snapshots_by_conversation
                .get("conv-2")
                .and_then(|items| items.last())
                .cloned()
                .unwrap();
            assert_eq!(latest.goal, "Operational plan in progress");
            assert_eq!(latest.steps.first().map(|step| step.id.as_str()), Some("7"));
            assert_eq!(
                latest.steps.first().map(|step| step.status.as_str()),
                Some("running")
            );
        });
    }

    #[test]
    fn create_snapshot_without_conversation_id_generates_new_conversation_when_empty() {
        with_temp_home(|| {
            let mut args = BTreeMap::new();
            args.insert("goal".to_string(), "Goal".to_string());
            args.insert(
                "steps".to_string(),
                r#"[{"step_id":"1","title":"Audit","status":"pending"}]"#.to_string(),
            );

            let message = create_snapshot(&args).unwrap();
            assert_eq!(message, "OK — plan snapshot created");

            let document = read_document();
            assert_eq!(document.snapshots_by_conversation.len(), 1);
            let generated_id = document
                .snapshots_by_conversation
                .keys()
                .next()
                .cloned()
                .unwrap();
            assert_eq!(
                document.latest_conversation_id.as_deref(),
                Some(generated_id.as_str())
            );
            assert_eq!(generated_id.len(), 36);
            assert_eq!(generated_id.matches('-').count(), 4);
        });
    }

    #[test]
    fn step_upsert_without_conversation_id_uses_unique_existing_snapshot() {
        with_temp_home(|| {
            let mut create_args = BTreeMap::new();
            create_args.insert("conversation_id".to_string(), "conv-unique".to_string());
            create_args.insert("goal".to_string(), "Goal".to_string());
            create_args.insert("steps".to_string(), "[]".to_string());
            create_snapshot(&create_args).unwrap();

            let mut args = BTreeMap::new();
            args.insert("step_id".to_string(), "7".to_string());
            args.insert("status".to_string(), "running".to_string());
            args.insert("title".to_string(), "Plan".to_string());
            let message = step_upsert(&args).unwrap();
            assert_eq!(message, "OK — plan step 7 upserted");

            let latest = read_document()
                .snapshots_by_conversation
                .get("conv-unique")
                .and_then(|items| items.last())
                .cloned()
                .unwrap();
            assert_eq!(latest.steps.first().map(|step| step.id.as_str()), Some("7"));
        });
    }

    #[test]
    fn create_snapshot_without_conversation_id_fails_when_multiple_snapshots_exist() {
        with_temp_home(|| {
            let mut create_a = BTreeMap::new();
            create_a.insert("conversation_id".to_string(), "conv-a".to_string());
            create_a.insert("goal".to_string(), "Plan A".to_string());
            create_a.insert("steps".to_string(), "[]".to_string());
            create_snapshot(&create_a).unwrap();

            let mut create_b = BTreeMap::new();
            create_b.insert("conversation_id".to_string(), "conv-b".to_string());
            create_b.insert("goal".to_string(), "Plan B".to_string());
            create_b.insert("steps".to_string(), "[]".to_string());
            create_snapshot(&create_b).unwrap();

            let mut ambiguous = BTreeMap::new();
            ambiguous.insert("goal".to_string(), "Ambiguous".to_string());
            ambiguous.insert("steps".to_string(), "[]".to_string());

            let error = create_snapshot(&ambiguous).unwrap_err();
            assert!(error.contains("unable to resolve target plan snapshot"));
        });
    }

    #[test]
    fn diff_reports_status_change() {
        with_temp_home(|| {
            let mut create_args = BTreeMap::new();
            create_args.insert("conversation_id".to_string(), "conv-3".to_string());
            create_args.insert("goal".to_string(), "Goal".to_string());
            create_args.insert(
                "steps".to_string(),
                r#"[{"step_id":"1","title":"Audit","status":"pending"}]"#.to_string(),
            );
            create_snapshot(&create_args).unwrap();

            let first_snapshot = read_document()
                .snapshots_by_conversation
                .get("conv-3")
                .and_then(|items| items.first())
                .map(|snapshot| snapshot.snapshot_id.clone())
                .unwrap();

            let mut update_args = BTreeMap::new();
            update_args.insert("conversation_id".to_string(), "conv-3".to_string());
            update_args.insert("step_id".to_string(), "1".to_string());
            update_args.insert("status".to_string(), "done".to_string());
            step_update(&update_args).unwrap();

            let mut diff_args = BTreeMap::new();
            diff_args.insert("from_snapshot_id".to_string(), first_snapshot);
            let diff_payload = diff(&diff_args).unwrap();
            assert!(diff_payload.contains("\"fromStatus\": \"pending\""));
            assert!(diff_payload.contains("\"toStatus\": \"done\""));
        });
    }
}
