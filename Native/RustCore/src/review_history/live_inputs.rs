use serde_json::Value;
use std::collections::HashMap;

pub(super) fn derive_live_workers_from_worker_plans(
    worker_plans: &[Value],
    active: bool,
) -> Vec<Value> {
    let mut workers = worker_plans
        .iter()
        .map(|plan| {
            let worker_id = plan
                .get("workerId")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let description = plan
                .get("description")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let severity = plan
                .get("severity")
                .and_then(Value::as_str)
                .unwrap_or("info");
            let file_count = plan
                .get("fileCount")
                .and_then(Value::as_i64)
                .unwrap_or_else(|| {
                    plan.get("files")
                        .and_then(Value::as_array)
                        .map(|items| items.len() as i64)
                        .unwrap_or(0)
                });
            serde_json::json!({
                "id": worker_id,
                "title": worker_id,
                "detail": description,
                "severity": severity,
                "status": if active { "running" } else { "completed" },
                "files": plan.get("files").cloned().unwrap_or_else(|| Value::Array(Vec::new())),
                "fileCount": file_count
            })
        })
        .collect::<Vec<_>>();
    workers.sort_by(|lhs, rhs| {
        lhs.get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .cmp(rhs.get("id").and_then(Value::as_str).unwrap_or_default())
    });
    workers
}

pub(super) fn derive_live_files_from_worker_plans(worker_plans: &[Value]) -> Vec<Value> {
    let mut aggregates: HashMap<String, (Vec<String>, String, String)> = HashMap::new();
    for plan in worker_plans {
        let worker_id = plan
            .get("workerId")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let severity = plan
            .get("severity")
            .and_then(Value::as_str)
            .unwrap_or("info")
            .to_string();
        let status = plan
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("running")
            .to_string();
        for path in plan
            .get("files")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(Value::as_str)
        {
            let entry = aggregates
                .entry(path.to_string())
                .or_insert_with(|| (Vec::new(), severity.clone(), status.clone()));
            if !entry.0.iter().any(|existing| existing == &worker_id) {
                entry.0.push(worker_id.clone());
            }
            if severity_rank(&severity) < severity_rank(&entry.1) {
                entry.1 = severity.clone();
            }
            entry.2 = merge_status(&entry.2, &status).to_string();
        }
    }
    live_files_from_aggregates(aggregates)
}

pub(super) fn derive_live_workers_from_live_cards(live_cards: &[Value]) -> Vec<Value> {
    let mut workers = live_cards
        .iter()
        .map(|card| {
            let worker_id = card.get("workerId").and_then(Value::as_str).filter(|value| !value.is_empty()).or_else(|| card.get("swarmId").and_then(Value::as_str)).unwrap_or_default();
            let warning_count = card.get("warningCount").and_then(Value::as_i64).unwrap_or(0);
            let files = card.get("files").cloned().unwrap_or_else(|| Value::Array(Vec::new()));
            let file_count = files.as_array().map(|items| items.len() as i64).unwrap_or(0);
            serde_json::json!({
                "id": worker_id,
                "title": card.get("displayName").and_then(Value::as_str).filter(|value| !value.is_empty()).unwrap_or(worker_id),
                "detail": card.get("currentStepTitle").and_then(Value::as_str).unwrap_or_default(),
                "severity": if warning_count > 0 { "warning" } else { "info" },
                "status": card.get("status").and_then(Value::as_str).unwrap_or("idle"),
                "files": files,
                "fileCount": file_count
            })
        })
        .collect::<Vec<_>>();
    workers.sort_by(|lhs, rhs| {
        lhs.get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .cmp(rhs.get("id").and_then(Value::as_str).unwrap_or_default())
    });
    workers
}

pub(super) fn derive_live_files_from_live_cards(live_cards: &[Value]) -> Vec<Value> {
    let mut aggregates: HashMap<String, (Vec<String>, String, String)> = HashMap::new();
    for card in live_cards {
        let worker_id = card
            .get("workerId")
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .or_else(|| card.get("swarmId").and_then(Value::as_str))
            .unwrap_or_default()
            .to_string();
        let severity = if card
            .get("warningCount")
            .and_then(Value::as_i64)
            .unwrap_or(0)
            > 0
        {
            "warning".to_string()
        } else {
            "info".to_string()
        };
        let status = card
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or("idle")
            .to_string();
        for path in card
            .get("files")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
            .iter()
            .filter_map(Value::as_str)
        {
            let entry = aggregates
                .entry(path.to_string())
                .or_insert_with(|| (Vec::new(), severity.clone(), status.clone()));
            if !entry.0.iter().any(|existing| existing == &worker_id) {
                entry.0.push(worker_id.clone());
            }
            if severity_rank(&severity) < severity_rank(&entry.1) {
                entry.1 = severity.clone();
            }
            entry.2 = merge_status(&entry.2, &status).to_string();
        }
    }
    live_files_from_aggregates(aggregates)
}

pub(super) fn compare_live_files(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
    let left_rank = lhs
        .get("severity")
        .and_then(Value::as_str)
        .map(severity_rank)
        .unwrap_or(99);
    let right_rank = rhs
        .get("severity")
        .and_then(Value::as_str)
        .map(severity_rank)
        .unwrap_or(99);
    left_rank
        .cmp(&right_rank)
        .then_with(|| file_name(lhs).cmp(&file_name(rhs)))
}

fn live_files_from_aggregates(
    aggregates: HashMap<String, (Vec<String>, String, String)>,
) -> Vec<Value> {
    let mut files = aggregates
        .into_iter()
        .map(|(path, (worker_ids, severity, status))| {
            serde_json::json!({
                "path": path,
                "workerIds": worker_ids,
                "severity": severity,
                "status": status
            })
        })
        .collect::<Vec<_>>();
    files.sort_by(compare_live_files);
    files
}

fn file_name(value: &Value) -> String {
    value
        .get("path")
        .and_then(Value::as_str)
        .and_then(|path| path.rsplit('/').next())
        .unwrap_or_default()
        .to_string()
}

fn severity_rank(severity: &str) -> i64 {
    match severity {
        "critical" => 0,
        "warning" => 1,
        "suggestion" => 2,
        "info" => 3,
        _ => 99,
    }
}

fn merge_status(lhs: &str, rhs: &str) -> &'static str {
    let rank = |status: &str| match status {
        "failed" => 0,
        "running" => 1,
        "completed" => 2,
        _ => 3,
    };
    if rank(lhs) <= rank(rhs) {
        map_file_status(Some(lhs))
    } else {
        map_file_status(Some(rhs))
    }
}

fn map_file_status(status: Option<&str>) -> &'static str {
    match status {
        Some("completed") => "completed",
        Some("running") => "running",
        Some("blocked") => "failed",
        _ => "idle",
    }
}
