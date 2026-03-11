use super::models::{ReviewPipelineSnapshot, ReviewTask};
use super::phases::{ledger_status, phase_title, PHASE_ORDER};
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeSet, HashMap};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelinePhaseLedgerEntry {
    pub id: String,
    pub title: String,
    pub status: String,
    pub file_count: i32,
    pub worker_count: i32,
    pub findings_count: i32,
    pub started_at: Option<f64>,
    pub completed_at: Option<f64>,
    pub summary: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineFileLedgerEntry {
    pub path: String,
    pub phase_id: String,
    pub status: String,
    pub worker_ids: Vec<String>,
    pub tool_ids: Vec<String>,
    pub severity: Option<String>,
    pub candidate_count: i32,
    pub finding_count: i32,
    pub patch_ready_count: i32,
    pub summary: Option<String>,
}

pub fn build_phase_ledger(
    snapshot: &ReviewPipelineSnapshot,
    current_phase: &str,
    terminal: bool,
) -> Vec<ReviewPipelinePhaseLedgerEntry> {
    PHASE_ORDER
        .iter()
        .map(|phase_id| ReviewPipelinePhaseLedgerEntry {
            id: (*phase_id).to_string(),
            title: phase_title(phase_id).to_string(),
            status: ledger_status(phase_id, current_phase, terminal).to_string(),
            file_count: snapshot.scope.as_ref().map(|scope| scope.files.len() as i32).unwrap_or(0),
            worker_count: snapshot.active_worker_count,
            findings_count: snapshot.findings.len() as i32,
            started_at: snapshot.started_at,
            completed_at: if terminal && *phase_id == "completed" {
                snapshot.completed_at
            } else {
                None
            },
            summary: Some(format!(
                "{} files, {} candidates, {} findings, {} patches",
                snapshot.scope.as_ref().map(|scope| scope.files.len()).unwrap_or(0),
                snapshot.candidates.len(),
                snapshot.findings.len(),
                snapshot.patches.len()
            )),
        })
        .collect()
}

pub fn build_file_ledger(
    snapshot: &ReviewPipelineSnapshot,
    current_tasks: &[ReviewTask],
) -> Vec<ReviewPipelineFileLedgerEntry> {
    let mut files = BTreeSet::new();
    if let Some(scope) = &snapshot.scope {
        files.extend(scope.files.iter().cloned());
    }
    files.extend(current_tasks.iter().flat_map(|task| task.files.iter().cloned()));
    files.extend(snapshot.findings.iter().filter_map(|finding| finding.get("filePath").and_then(Value::as_str).map(ToString::to_string)));
    files.extend(snapshot.candidates.iter().filter_map(|candidate| candidate.get("filePath").and_then(Value::as_str).map(ToString::to_string)));
    files.extend(snapshot.patches.iter().flat_map(|patch| {
        patch.get("touchedFiles")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(ToString::to_string)
            .collect::<Vec<_>>()
    }));

    let task_map = tasks_by_file(current_tasks);
    let tool_ids = snapshot.audit.pointer("/toolCoverage").and_then(Value::as_object).map(|items| {
        items.keys().cloned().collect::<Vec<_>>()
    }).unwrap_or_default();

    files
        .into_iter()
        .map(|path| {
            let tasks = task_map.get(&path).cloned().unwrap_or_default();
            let candidate_count = count_by_file(&snapshot.candidates, &path);
            let finding_count = count_by_file(&snapshot.findings, &path);
            let patch_ready_count = snapshot
                .patches
                .iter()
                .filter(|patch| {
                    patch.get("status").and_then(Value::as_str).map(is_patch_ready).unwrap_or(false)
                        && patch
                            .get("touchedFiles")
                            .and_then(Value::as_array)
                            .map(|items| items.iter().filter_map(Value::as_str).any(|item| item == path))
                            .unwrap_or(false)
                })
                .count() as i32;
            let severity = highest_severity(&snapshot.findings, &snapshot.candidates, &path);
            let (phase_id, status) = classify_file_ledger_state(candidate_count, finding_count, patch_ready_count, !tasks.is_empty(), !tool_ids.is_empty());
            ReviewPipelineFileLedgerEntry {
                path,
                phase_id: phase_id.to_string(),
                status: status.to_string(),
                worker_ids: tasks.iter().map(|task| task.id.clone()).collect(),
                tool_ids: tool_ids.clone(),
                severity,
                candidate_count,
                finding_count,
                patch_ready_count,
                summary: Some(format!(
                    "{} candidate(s), {} finding(s), {} patch-ready",
                    candidate_count, finding_count, patch_ready_count
                )),
            }
        })
        .collect()
}

fn tasks_by_file(tasks: &[ReviewTask]) -> HashMap<String, Vec<ReviewTask>> {
    let mut out: HashMap<String, Vec<ReviewTask>> = HashMap::new();
    for task in tasks {
        for file in &task.files {
            out.entry(file.clone()).or_default().push(task.clone());
        }
    }
    out
}

fn count_by_file(items: &[Value], path: &str) -> i32 {
    items
        .iter()
        .filter(|item| item.get("filePath").and_then(Value::as_str) == Some(path))
        .count() as i32
}

fn highest_severity(findings: &[Value], candidates: &[Value], path: &str) -> Option<String> {
    findings
        .iter()
        .chain(candidates.iter())
        .filter(|item| item.get("filePath").and_then(Value::as_str) == Some(path))
        .filter_map(|item| item.get("severity").and_then(Value::as_str))
        .min_by_key(|severity| severity_rank(severity))
        .map(ToString::to_string)
}

fn severity_rank(severity: &str) -> i32 {
    match severity {
        "critical" => 0,
        "warning" => 1,
        "suggestion" => 2,
        "info" => 3,
        _ => 4,
    }
}

fn classify_file_ledger_state(
    candidate_count: i32,
    finding_count: i32,
    patch_ready_count: i32,
    has_assignment: bool,
    has_tools: bool,
) -> (&'static str, &'static str) {
    if patch_ready_count > 0 {
        ("publish_ready", "completed")
    } else if finding_count > 0 {
        ("verification", "running")
    } else if candidate_count > 0 {
        ("verification", "running")
    } else if has_assignment {
        ("discovery", "running")
    } else if has_tools {
        ("audit", "completed")
    } else {
        ("queued", "pending")
    }
}

fn is_patch_ready(status: &str) -> bool {
    matches!(status, "verified" | "applied" | "prOpened" | "merged")
}
