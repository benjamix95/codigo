mod snapshot;

pub use snapshot::derive_historical_findings_from_snapshot;

use serde_json::Value;
use std::collections::HashMap;

pub fn shape_historical_findings(records: Vec<Value>) -> Vec<Value> {
    let mut merged: HashMap<String, Value> = HashMap::new();
    for mut record in records {
        normalize_timeline(&mut record);
        let Some(finding_id) = record.get("findingId").and_then(Value::as_str) else {
            continue;
        };
        let replace = merged
            .get(finding_id)
            .map(|existing| updated_at(&record) > updated_at(existing))
            .unwrap_or(true);
        if replace {
            merged.insert(finding_id.to_string(), record);
        }
    }
    let mut items = merged.into_values().collect::<Vec<_>>();
    items.sort_by(compare_records);
    items
}

pub fn derive_history_live_state(snapshot: &Value) -> Value {
    let file_ledger = snapshot
        .get("fileLedger")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let workers = derive_live_workers(&file_ledger, is_active(snapshot));
    let files = derive_live_files(&file_ledger);
    serde_json::json!({
        "title": if is_active(snapshot) { "Live Review Board" } else { "Completed Run Summary" },
        "subtitle": if is_active(snapshot) {
            "File e worker aggiornati in tempo reale durante la review corrente."
        } else {
            "Ultimo run congelato con dettaglio operativo enterprise-grade."
        },
        "workers": workers,
        "files": files,
        "isRunning": is_active(snapshot),
    })
}

fn normalize_timeline(record: &mut Value) {
    if let Some(timeline) = record.get_mut("timeline").and_then(Value::as_array_mut) {
        timeline.sort_by(|lhs, rhs| {
            let lhs_created = lhs.get("createdAt").and_then(Value::as_str).unwrap_or_default();
            let rhs_created = rhs.get("createdAt").and_then(Value::as_str).unwrap_or_default();
            lhs_created.cmp(rhs_created)
        });
    }
}

fn compare_records(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
    match (resume_eligible(lhs), resume_eligible(rhs)) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => updated_at(rhs)
            .partial_cmp(&updated_at(lhs))
            .unwrap_or(std::cmp::Ordering::Equal),
    }
}

fn resume_eligible(value: &Value) -> bool {
    value.get("resumeEligible").and_then(Value::as_bool).unwrap_or(false)
}

fn updated_at(value: &Value) -> f64 {
    value.get("updatedAt").and_then(Value::as_f64).unwrap_or(0.0)
}

fn is_active(snapshot: &Value) -> bool {
    matches!(
        snapshot.get("phase").and_then(Value::as_str),
        Some("analyzing") | Some("fixing") | Some("testing") | Some("re_reviewing")
    )
}

fn derive_live_workers(file_ledger: &[Value], active: bool) -> Vec<Value> {
    let mut grouped: HashMap<String, Vec<&Value>> = HashMap::new();
    for entry in file_ledger {
        let worker_ids = entry
            .get("workerIds")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        for worker_id in worker_ids.iter().filter_map(Value::as_str) {
            grouped.entry(worker_id.to_string()).or_default().push(entry);
        }
    }

    let mut workers = grouped
        .into_iter()
        .map(|(worker_id, entries)| {
            let files = entries
                .iter()
                .filter_map(|entry| entry.get("path").and_then(Value::as_str))
                .map(ToString::to_string)
                .collect::<Vec<_>>();
            let detail = entries
                .iter()
                .filter_map(|entry| entry.get("phaseId").and_then(Value::as_str))
                .collect::<Vec<_>>()
                .join(" -> ");
            serde_json::json!({
                "id": worker_id,
                "title": worker_id,
                "detail": detail,
                "severity": highest_severity(&entries),
                "status": if active { "running" } else { "completed" },
                "files": files,
                "fileCount": entries.len()
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

fn derive_live_files(file_ledger: &[Value]) -> Vec<Value> {
    let mut files = file_ledger
        .iter()
        .map(|entry| {
            serde_json::json!({
                "path": entry.get("path").cloned().unwrap_or(Value::Null),
                "workerIds": entry.get("workerIds").cloned().unwrap_or_else(|| Value::Array(Vec::new())),
                "severity": entry.get("severity").cloned().unwrap_or(Value::String("info".to_string())),
                "status": map_file_status(entry.get("status").and_then(Value::as_str))
            })
        })
        .collect::<Vec<_>>();

    files.sort_by(compare_live_files);
    files
}

fn highest_severity(entries: &[&Value]) -> String {
    entries
        .iter()
        .filter_map(|entry| entry.get("severity").and_then(Value::as_str))
        .min_by_key(|severity| severity_rank(severity))
        .unwrap_or("info")
        .to_string()
}

fn map_file_status(status: Option<&str>) -> &'static str {
    match status {
        Some("completed") => "completed",
        Some("running") => "running",
        Some("blocked") => "failed",
        _ => "idle",
    }
}

fn compare_live_files(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
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

fn file_name(value: &Value) -> String {
    value.get("path")
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn sorts_resume_first_then_updated_desc() {
        let shaped = shape_historical_findings(vec![
            json!({"findingId":"a","resumeEligible":false,"updatedAt":1.0,"timeline":[]}),
            json!({"findingId":"b","resumeEligible":true,"updatedAt":0.5,"timeline":[]}),
            json!({"findingId":"c","resumeEligible":true,"updatedAt":2.0,"timeline":[]}),
        ]);
        assert_eq!(shaped[0]["findingId"].as_str(), Some("c"));
        assert_eq!(shaped[1]["findingId"].as_str(), Some("b"));
        assert_eq!(shaped[2]["findingId"].as_str(), Some("a"));
    }

    #[test]
    fn derives_history_live_state_from_file_ledger() {
        let state = derive_history_live_state(&json!({
            "phase": "completed",
            "fileLedger": [
                {"path": "Sources/A.swift", "phaseId": "verification", "status": "running", "workerIds": ["worker-1"], "severity": "warning"},
                {"path": "Sources/B.swift", "phaseId": "publish_ready", "status": "completed", "workerIds": ["worker-1"], "severity": "critical"}
            ]
        }));
        assert_eq!(state["workers"][0]["id"].as_str(), Some("worker-1"));
        assert_eq!(state["files"][0]["path"].as_str(), Some("Sources/B.swift"));
        assert_eq!(state["files"][0]["status"].as_str(), Some("completed"));
        assert_eq!(state["isRunning"].as_bool(), Some(false));
    }
}
