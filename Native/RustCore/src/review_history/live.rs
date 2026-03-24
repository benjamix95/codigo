use super::live_inputs::{
    compare_live_files, derive_live_files_from_live_cards, derive_live_files_from_worker_plans,
    derive_live_workers_from_live_cards, derive_live_workers_from_worker_plans,
};
use serde_json::Value;
use std::collections::HashMap;

pub fn derive_history_live_state(
    snapshot: &Value,
    worker_plans: &[Value],
    live_cards: &[Value],
) -> Value {
    let file_ledger = snapshot
        .get("fileLedger")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let workers = if !file_ledger.is_empty() {
        derive_live_workers(&file_ledger, is_active(snapshot))
    } else if !worker_plans.is_empty() {
        derive_live_workers_from_worker_plans(worker_plans, is_active(snapshot))
    } else {
        derive_live_workers_from_live_cards(live_cards)
    };
    let files = if !file_ledger.is_empty() {
        derive_live_files(&file_ledger)
    } else if !worker_plans.is_empty() {
        derive_live_files_from_worker_plans(worker_plans)
    } else {
        derive_live_files_from_live_cards(live_cards)
    };
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
            grouped
                .entry(worker_id.to_string())
                .or_default()
                .push(entry);
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

fn severity_rank(severity: &str) -> i64 {
    match severity {
        "critical" => 0,
        "warning" => 1,
        "suggestion" => 2,
        "info" => 3,
        _ => 99,
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

#[cfg(test)]
mod tests {
    use super::derive_history_live_state;
    use serde_json::json;

    #[test]
    fn derives_history_live_state_from_file_ledger() {
        let state = derive_history_live_state(
            &json!({
                "phase": "completed",
                "fileLedger": [
                    {"path": "Sources/A.swift", "phaseId": "verification", "status": "running", "workerIds": ["worker-1"], "severity": "warning"},
                    {"path": "Sources/B.swift", "phaseId": "publish_ready", "status": "completed", "workerIds": ["worker-1"], "severity": "critical"}
                ]
            }),
            &[],
            &[],
        );
        assert_eq!(state["workers"][0]["id"].as_str(), Some("worker-1"));
        assert_eq!(state["files"][0]["path"].as_str(), Some("Sources/B.swift"));
        assert_eq!(state["files"][0]["status"].as_str(), Some("completed"));
        assert_eq!(state["isRunning"].as_bool(), Some(false));
    }

    #[test]
    fn derives_history_live_state_from_worker_plans_when_file_ledger_is_empty() {
        let state = derive_history_live_state(
            &json!({ "phase": "analyzing", "fileLedger": [] }),
            &[
                json!({
                    "workerId": "worker-1",
                    "description": "Analyze retry paths",
                    "severity": "warning",
                    "files": ["Sources/A.swift", "Sources/B.swift"],
                    "fileCount": 2
                }),
                json!({
                    "workerId": "worker-2",
                    "description": "Analyze auth guards",
                    "severity": "critical",
                    "files": ["Sources/B.swift"],
                    "fileCount": 1
                }),
            ],
            &[],
        );
        assert_eq!(state["workers"][0]["id"].as_str(), Some("worker-1"));
        assert_eq!(state["files"][0]["path"].as_str(), Some("Sources/B.swift"));
        assert_eq!(
            state["files"][0]["workerIds"]
                .as_array()
                .map(|items| items.len()),
            Some(2)
        );
        assert_eq!(state["isRunning"].as_bool(), Some(true));
    }
}
