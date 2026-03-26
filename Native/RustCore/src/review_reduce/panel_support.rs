use crate::review_pipeline::phases::{
    phase_title, AUDIT, COMPLETED, DISCOVERY, PATCH_PREPARATION, PUBLISH_READY, VERIFICATION,
};
use crate::review_value::{get_i64, get_str};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};

pub fn build_phase_ledger(snapshot: &Value, current_phase: &str) -> Vec<Value> {
    let file_count = snapshot
        .pointer("/scope/files")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let worker_count = snapshot
        .get("activeWorkerCount")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let findings_count = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);
    let terminal = matches!(
        get_str(snapshot, "phase"),
        Some("completed") | Some("failed")
    ) && current_phase == COMPLETED;
    [DISCOVERY, AUDIT, VERIFICATION, PATCH_PREPARATION, PUBLISH_READY, COMPLETED]
        .iter()
        .map(|phase_id| {
            json!({
                "id": phase_id,
                "title": phase_title(phase_id),
                "status": ledger_status(phase_id, current_phase, terminal),
                "fileCount": file_count,
                "workerCount": worker_count,
                "findingsCount": findings_count,
                "startedAt": snapshot.get("startedAt").cloned().unwrap_or(Value::Null),
                "completedAt": if *phase_id == COMPLETED && terminal { snapshot.get("completedAt").cloned().unwrap_or(Value::Null) } else { Value::Null },
                "summary": format!("{} files, {} workers, {} findings", file_count, worker_count, findings_count)
            })
        })
        .collect()
}

pub fn build_file_ledger(
    snapshot: &Value,
    findings: &[Value],
    candidates: &[Value],
    patches: &[Value],
) -> Vec<Value> {
    let mut seed: BTreeMap<String, (Vec<String>, Vec<String>)> = BTreeMap::new();
    if let Some(existing) = snapshot.get("fileLedger").and_then(Value::as_array) {
        for item in existing {
            let Some(path) = get_str(item, "path") else {
                continue;
            };
            let workers = item
                .get("workerIds")
                .and_then(Value::as_array)
                .map(|values| values_to_strings(values))
                .unwrap_or_default();
            let tools = item
                .get("toolIds")
                .and_then(Value::as_array)
                .map(|values| values_to_strings(values))
                .unwrap_or_default();
            seed.insert(path.to_string(), (workers, tools));
        }
    }
    if let Some(scope_files) = snapshot.pointer("/scope/files").and_then(Value::as_array) {
        for path in scope_files.iter().filter_map(Value::as_str) {
            seed.entry(path.to_string())
                .or_insert_with(|| (Vec::new(), Vec::new()));
        }
    }
    for item in findings.iter().chain(candidates.iter()) {
        if let Some(path) = get_str(item, "filePath") {
            seed.entry(path.to_string())
                .or_insert_with(|| (Vec::new(), Vec::new()));
        }
    }
    for patch in patches {
        if let Some(files) = patch.get("touchedFiles").and_then(Value::as_array) {
            for path in files.iter().filter_map(Value::as_str) {
                seed.entry(path.to_string())
                    .or_insert_with(|| (Vec::new(), Vec::new()));
            }
        }
    }

    seed.into_iter().map(|(path, (worker_ids, mut tool_ids))| {
        if tool_ids.is_empty() {
            tool_ids = snapshot.pointer("/audit/toolCoverage").and_then(Value::as_object).map(|items| items.keys().cloned().collect()).unwrap_or_default();
        }
        let candidate_count = count_by_file(candidates, &path);
        let finding_count = count_by_file(findings, &path);
        let patch_ready_count = count_patch_ready(patches, &path);
        let severity = highest_severity(findings, candidates, &path);
        let (phase_id, status) = if patch_ready_count > 0 {
            (PUBLISH_READY, "completed")
        } else if finding_count > 0 || candidate_count > 0 {
            (VERIFICATION, "running")
        } else if !tool_ids.is_empty() {
            (AUDIT, "completed")
        } else {
            (DISCOVERY, "pending")
        };
        json!({
            "path": path,
            "phaseId": phase_id,
            "status": status,
            "workerIds": worker_ids,
            "toolIds": tool_ids,
            "severity": severity,
            "candidateCount": candidate_count,
            "findingCount": finding_count,
            "patchReadyCount": patch_ready_count,
            "summary": format!("{} candidate(s), {} finding(s), {} patch-ready", candidate_count, finding_count, patch_ready_count)
        })
    }).collect()
}

pub fn tool_executions(snapshot: &Value, _pipeline_phase: &str) -> Vec<Value> {
    let coverage = snapshot
        .pointer("/audit/toolCoverage")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let findings_counts = snapshot
        .pointer("/audit/toolFindingsCounts")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    if !coverage.is_empty() {
        return coverage
            .keys()
            .cloned()
            .collect::<Vec<_>>()
            .into_iter()
            .map(|tool| {
                json!({
                    "id": tool,
                    "status": "completed",
                    "findingsCount": findings_counts.get(&tool).and_then(Value::as_i64).unwrap_or(0)
                })
            })
            .collect();
    }
    // Allineato a `ReviewPipelineJobStateBuilder.toolExecutions` (Swift): solo i primi
    // `tools_running_cap` slot sono "running", non tutti i bundle durante DISCOVERY/AUDIT.
    // Altrimenti l’anello UI pesava 0.42 su ogni tool → (0.42*N)/N = 42% con N=3 anche con 0/3 completati.
    let modes = bundle_modes(snapshot);
    if modes.is_empty() {
        return Vec::new();
    }
    let tools_completed: usize = 0;
    let n = modes.len();
    let phase_str = get_str(snapshot, "phase").unwrap_or("");
    let session_active = matches!(
        phase_str,
        "analyzing" | "fixing" | "testing" | "re_reviewing"
    );
    let workers = snapshot
        .get("activeWorkerCount")
        .and_then(Value::as_i64)
        .unwrap_or(0) as usize;
    let tools_running_cap = if session_active {
        workers.max(1).min(n.saturating_sub(tools_completed))
    } else {
        0
    };
    modes
        .into_iter()
        .enumerate()
        .map(|(idx, mode)| {
            let status = if idx < tools_completed {
                "completed"
            } else if idx < tools_completed + tools_running_cap {
                "running"
            } else {
                "pending"
            };
            json!({
                "id": mode,
                "status": status,
                "findingsCount": 0
            })
        })
        .collect()
}

pub fn bundle_modes(snapshot: &Value) -> Vec<String> {
    if snapshot.get("startedAt").is_some()
        || !snapshot
            .get("events")
            .and_then(Value::as_array)
            .unwrap_or(&Vec::new())
            .is_empty()
    {
        vec![
            "standard".to_string(),
            "bugFinder".to_string(),
            "securityAudit".to_string(),
        ]
    } else {
        Vec::new()
    }
}

pub fn severity_counts(findings: &[Value], ids: &HashSet<String>) -> BTreeMap<String, i64> {
    let mut out = BTreeMap::new();
    for finding in findings {
        let Some(id) = get_str(finding, "id") else {
            continue;
        };
        let Some(severity) = get_str(finding, "severity") else {
            continue;
        };
        if ids.contains(id) {
            *out.entry(severity.to_string()).or_insert(0) += 1;
        }
    }
    out
}

pub fn sorted_ids(ids: &HashSet<String>, findings: &[Value]) -> Vec<String> {
    let mut out = ids.iter().cloned().collect::<Vec<_>>();
    out.sort_by(|lhs, rhs| compare_finding(lhs, rhs, findings));
    out
}

fn compare_finding(lhs: &str, rhs: &str, findings: &[Value]) -> std::cmp::Ordering {
    let left = findings
        .iter()
        .find(|finding| get_str(finding, "id") == Some(lhs));
    let right = findings
        .iter()
        .find(|finding| get_str(finding, "id") == Some(rhs));
    let left_rank = left
        .and_then(|finding| severity_rank(get_str(finding, "severity")))
        .unwrap_or(99);
    let right_rank = right
        .and_then(|finding| severity_rank(get_str(finding, "severity")))
        .unwrap_or(99);
    left_rank
        .cmp(&right_rank)
        .then_with(|| {
            left.and_then(|finding| get_str(finding, "filePath"))
                .unwrap_or("")
                .cmp(
                    right
                        .and_then(|finding| get_str(finding, "filePath"))
                        .unwrap_or(""),
                )
        })
        .then_with(|| {
            left.and_then(|finding| get_i64(finding, "lineNumber"))
                .unwrap_or(0)
                .cmp(
                    &right
                        .and_then(|finding| get_i64(finding, "lineNumber"))
                        .unwrap_or(0),
                )
        })
        .then_with(|| lhs.cmp(rhs))
}

fn count_by_file(items: &[Value], path: &str) -> i64 {
    items
        .iter()
        .filter(|item| get_str(item, "filePath") == Some(path))
        .count() as i64
}

fn count_patch_ready(patches: &[Value], path: &str) -> i64 {
    patches
        .iter()
        .filter(|patch| {
            matches!(
                get_str(patch, "status"),
                Some("verified") | Some("applied") | Some("prOpened") | Some("merged")
            ) && patch
                .get("touchedFiles")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .any(|item| item == path)
                })
                .unwrap_or(false)
        })
        .count() as i64
}

fn highest_severity(findings: &[Value], candidates: &[Value], path: &str) -> Option<String> {
    findings
        .iter()
        .chain(candidates.iter())
        .filter(|item| get_str(item, "filePath") == Some(path))
        .filter_map(|item| get_str(item, "severity"))
        .min_by_key(|severity| severity_rank(Some(severity)).unwrap_or(99))
        .map(ToString::to_string)
}

fn ledger_status(phase_id: &str, current_phase: &str, terminal: bool) -> &'static str {
    let target = phase_rank(phase_id);
    let current = phase_rank(current_phase);
    if terminal && current_phase == COMPLETED {
        "completed"
    } else if target < current {
        "completed"
    } else if target == current {
        "running"
    } else {
        "pending"
    }
}

fn phase_rank(phase_id: &str) -> i64 {
    match phase_id {
        DISCOVERY => 1,
        AUDIT => 2,
        VERIFICATION => 3,
        PATCH_PREPARATION => 4,
        PUBLISH_READY => 5,
        COMPLETED => 6,
        _ => 0,
    }
}

fn severity_rank(severity: Option<&str>) -> Option<i64> {
    match severity {
        Some("critical") => Some(0),
        Some("warning") => Some(1),
        Some("suggestion") => Some(2),
        Some("info") => Some(3),
        _ => None,
    }
}

fn values_to_strings(values: &[Value]) -> Vec<String> {
    values
        .iter()
        .filter_map(Value::as_str)
        .map(ToString::to_string)
        .collect()
}
