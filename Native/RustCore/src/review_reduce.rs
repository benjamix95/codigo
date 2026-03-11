use crate::review_value::{get_bool, get_str};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

pub fn merge_history(primary: Vec<Value>, fallback: Vec<Value>) -> Vec<Value> {
    let mut merged: HashMap<String, Value> = primary
        .into_iter()
        .filter_map(|record| Some((get_str(&record, "findingId")?.to_string(), record)))
        .collect();

    for record in fallback {
        let Some(finding_id) = get_str(&record, "findingId") else { continue };
        let replace = merged
            .get(finding_id)
            .map(|existing| updated_at(&record) > updated_at(existing))
            .unwrap_or(true);
        if replace {
            merged.insert(finding_id.to_string(), record);
        }
    }

    let mut values: Vec<Value> = merged.into_values().collect();
    values.sort_by(|lhs, rhs| compare_history(lhs, rhs));
    values
}

pub fn derive_review_panel_state(snapshot: Value) -> Value {
    let findings = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let patches = snapshot
        .get("patches")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let verified_queue = snapshot
        .pointer("/verifiedFindings/projectionSnapshot/verifiedQueue")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let candidate_queue = snapshot
        .pointer("/verifiedFindings/projectionSnapshot/candidateQueue")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let audit_coverage = snapshot
        .pointer("/audit/toolCoverage")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let audit_findings_counts = snapshot
        .pointer("/audit/toolFindingsCounts")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let verified_ids: HashSet<String> = verified_queue
        .iter()
        .filter_map(|item| get_str(item, "id").map(ToString::to_string))
        .collect();
    let patches_by_finding_id: HashMap<String, Value> = patches
        .iter()
        .filter_map(|patch| {
            get_str(patch, "findingId")
                .map(|finding_id| (finding_id.to_string(), patch.clone()))
        })
        .collect();

    let published_finding_ids: Vec<String> = findings
        .iter()
        .filter_map(|finding| {
            let finding_id = get_str(finding, "id")?;
            if !verified_ids.contains(finding_id) || !finding_is_verified(finding) {
                return None;
            }
            let patch_id = get_str(finding, "patchArtifactId")?;
            let patch = patches_by_finding_id.get(finding_id)?;
            if get_str(patch, "id") != Some(patch_id) {
                return None;
            }
            if get_str(patch, "verifyStatus") != Some("verified") {
                return None;
            }
            match get_str(patch, "status") {
                Some("verified") | Some("applied") | Some("prOpened") | Some("merged") => {
                    Some(finding_id.to_string())
                }
                _ => None,
            }
        })
        .collect();

    let bundle_modes = if snapshot.get("startedAt").is_some()
        || get_str(&snapshot, "phase").unwrap_or("idle") != "idle"
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
    };

    let tools_total = std::cmp::max(audit_coverage.len(), bundle_modes.len());
    let tools_completed = audit_coverage.len();
    let active_worker_count = snapshot
        .get("activeWorkerCount")
        .and_then(Value::as_i64)
        .unwrap_or(0)
        .max(0) as usize;
    let is_active = matches!(
        get_str(&snapshot, "phase"),
        Some("analyzing") | Some("fixing") | Some("testing") | Some("re_reviewing")
    );
    let tools_running = if is_active {
        std::cmp::min(
            std::cmp::max(active_worker_count, 1),
            tools_total.saturating_sub(tools_completed),
        )
    } else {
        0
    };
    let verification_gate_ready =
        verification_gate_ready(&findings, &verified_ids, get_str(&snapshot, "phase"));
    let patch_gate_ready = patch_gate_ready(&findings, &patches_by_finding_id, &verified_ids, get_str(&snapshot, "phase"));
    let published_finding_count = published_finding_ids.len();
    let pipeline_phase = pipeline_phase(
        &snapshot,
        tools_total,
        tools_completed,
        verification_gate_ready,
        patch_gate_ready,
        published_finding_count > 0 || (verification_gate_ready && patch_gate_ready && get_str(&snapshot, "phase") != Some("idle")),
    );
    let steps_completed = steps_completed(&pipeline_phase);
    let progress_percent = progress_percent(
        &pipeline_phase,
        &snapshot,
        &findings,
        &verified_ids,
        &patches_by_finding_id,
        tools_total,
        tools_completed,
    );

    let tool_executions = if !audit_coverage.is_empty() {
        let mut tool_names: Vec<String> = audit_coverage.keys().cloned().collect();
        tool_names.sort();
        tool_names
            .into_iter()
            .map(|tool_name| {
                json!({
                    "id": tool_name,
                    "status": "completed",
                    "findingsCount": audit_findings_counts.get(&tool_name).and_then(Value::as_i64).unwrap_or(0)
                })
            })
            .collect::<Vec<_>>()
    } else {
        bundle_modes
            .iter()
            .enumerate()
            .map(|(index, mode)| {
                let status = if index < tools_completed {
                    "completed"
                } else if index < tools_completed + tools_running {
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
            .collect::<Vec<_>>()
    };

    json!({
        "publishedFindingIds": published_finding_ids,
        "pipelinePhase": pipeline_phase,
        "progressPercent": progress_percent,
        "stepsCompleted": steps_completed,
        "stepsTotal": 6,
        "toolsTotal": tools_total,
        "toolsCompleted": tools_completed,
        "toolsRunning": tools_running,
        "candidateCount": candidate_queue.len(),
        "verifiedCount": verified_queue.len(),
        "publishedFindingCount": published_finding_count,
        "hiddenFindingCount": findings.len().saturating_sub(published_finding_count),
        "verificationGateReady": verification_gate_ready,
        "patchGateReady": patch_gate_ready,
        "bundleModes": bundle_modes,
        "toolExecutions": tool_executions,
        "isTerminal": matches!(get_str(&snapshot, "phase"), Some("completed") | Some("failed"))
    })
}

fn finding_is_verified(finding: &Value) -> bool {
    !finding.get("verifiedAt").unwrap_or(&Value::Null).is_null()
        || !finding
            .get("verificationReport")
            .unwrap_or(&Value::Null)
            .is_null()
}

fn verification_gate_ready(
    findings: &[Value],
    verified_ids: &HashSet<String>,
    phase: Option<&str>,
) -> bool {
    if verified_ids.is_empty() {
        return matches!(phase, Some("completed")) || findings.is_empty();
    }
    verified_ids.iter().all(|id| {
        findings.iter().any(|finding| {
            get_str(finding, "id") == Some(id.as_str()) && finding_is_verified(finding)
        })
    })
}

fn patch_gate_ready(
    findings: &[Value],
    patches_by_finding_id: &HashMap<String, Value>,
    verified_ids: &HashSet<String>,
    phase: Option<&str>,
) -> bool {
    if verified_ids.is_empty() {
        return matches!(phase, Some("completed")) || findings.is_empty();
    }
    verified_ids.iter().all(|id| {
        findings.iter().any(|finding| {
            if get_str(finding, "id") != Some(id.as_str()) {
                return false;
            }
            let Some(patch_id) = get_str(finding, "patchArtifactId") else { return false; };
            let Some(patch) = patches_by_finding_id.get(id) else { return false; };
            if get_str(patch, "id") != Some(patch_id) || get_str(patch, "verifyStatus") != Some("verified") {
                return false;
            }
            matches!(get_str(patch, "status"), Some("verified") | Some("applied") | Some("prOpened") | Some("merged"))
        })
    })
}

fn pipeline_phase(
    snapshot: &Value,
    tools_total: usize,
    tools_completed: usize,
    verification_gate_ready: bool,
    patch_gate_ready: bool,
    publish_ready: bool,
) -> String {
    if get_str(snapshot, "phase") == Some("completed") {
        return "completed".to_string();
    }
    if publish_ready {
        return "publish_ready".to_string();
    }
    if verification_gate_ready && !patch_gate_ready {
        return "patch_preparation".to_string();
    }
    let has_analysis_signal = snapshot.get("analysisCompletedAt").is_some()
        || snapshot
            .get("candidates")
            .and_then(Value::as_array)
            .map(|items| !items.is_empty())
            .unwrap_or(false)
        || snapshot
            .get("findings")
            .and_then(Value::as_array)
            .map(|items| !items.is_empty())
            .unwrap_or(false);
    if !verification_gate_ready && has_analysis_signal {
        return "verification".to_string();
    }
    if tools_total > 0 && tools_completed > 0 {
        return "audit".to_string();
    }
    if snapshot.get("startedAt").is_some() || get_str(snapshot, "phase") == Some("analyzing") {
        return "discovery".to_string();
    }
    "queued".to_string()
}

fn steps_completed(phase: &str) -> i64 {
    match phase {
        "completed" => 6,
        "publish_ready" => 5,
        "patch_preparation" => 4,
        "verification" => 3,
        "audit" => 2,
        "discovery" => 1,
        _ => 0,
    }
}

fn progress_percent(
    phase: &str,
    snapshot: &Value,
    findings: &[Value],
    verified_ids: &HashSet<String>,
    patches_by_finding_id: &HashMap<String, Value>,
    tools_total: usize,
    tools_completed: usize,
) -> i64 {
    match phase {
        "completed" => 100,
        "publish_ready" => 90,
        "patch_preparation" => {
            let ready_patches = findings.iter().filter(|finding| {
                let Some(id) = get_str(finding, "id") else { return false; };
                if !verified_ids.contains(id) {
                    return false;
                }
                let Some(patch_id) = get_str(finding, "patchArtifactId") else { return false; };
                let Some(patch) = patches_by_finding_id.get(id) else { return false; };
                get_str(patch, "id") == Some(patch_id)
                    && get_str(patch, "verifyStatus") == Some("verified")
                    && matches!(get_str(patch, "status"), Some("verified") | Some("applied") | Some("prOpened") | Some("merged"))
            }).count();
            let total = std::cmp::max(verified_ids.len(), 1);
            65 + ((ready_patches as f64 / total as f64) * 23.0) as i64
        }
        "verification" => {
            let verified = findings.iter().filter(|finding| {
                let Some(id) = get_str(finding, "id") else { return false; };
                verified_ids.contains(id) && finding_is_verified(finding)
            }).count();
            let total = std::cmp::max(verified_ids.len(), std::cmp::max(findings.len(), 1));
            45 + ((verified as f64 / total as f64) * 20.0) as i64
        }
        "audit" => {
            let total = std::cmp::max(tools_total, 1);
            20 + ((tools_completed as f64 / total as f64) * 20.0) as i64
        }
        "discovery" => {
            if tools_completed > 0 { 18 } else { 8 }
        }
        _ => {
            if snapshot.get("startedAt").is_none() { 0 } else { 4 }
        }
    }
}

fn compare_history(lhs: &Value, rhs: &Value) -> std::cmp::Ordering {
    match (get_bool(lhs, "resumeEligible"), get_bool(rhs, "resumeEligible")) {
        (true, false) => std::cmp::Ordering::Less,
        (false, true) => std::cmp::Ordering::Greater,
        _ => updated_at(rhs)
            .partial_cmp(&updated_at(lhs))
            .unwrap_or(std::cmp::Ordering::Equal),
    }
}

fn updated_at(value: &Value) -> f64 {
    value.get("updatedAt").and_then(Value::as_f64).unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_history_prefers_newer_and_resume_eligible() {
        let merged = merge_history(
            vec![json!({"findingId": "a", "resumeEligible": false, "updatedAt": 1.0})],
            vec![
                json!({"findingId": "a", "resumeEligible": true, "updatedAt": 2.0}),
                json!({"findingId": "b", "resumeEligible": false, "updatedAt": 3.0}),
            ],
        );
        assert_eq!(merged[0]["findingId"].as_str(), Some("a"));
        assert_eq!(merged[1]["findingId"].as_str(), Some("b"));
    }

    #[test]
    fn derive_review_panel_state_marks_hidden_findings_until_patch_ready() {
        let derived = derive_review_panel_state(json!({
            "phase": "analyzing",
            "startedAt": "2026-03-11T12:00:00Z",
            "activeWorkerCount": 1,
            "analysisCompletedAt": "2026-03-11T12:00:05Z",
            "findings": [{
                "id": "finding-1",
                "verifiedAt": "2026-03-11T12:00:06Z",
                "verificationReport": "verified",
                "patchArtifactId": "patch-1"
            }],
            "patches": [{
                "id": "patch-1",
                "findingId": "finding-1",
                "status": "draft",
                "verifyStatus": "pending"
            }],
            "audit": {
                "toolCoverage": {"standard": true},
                "toolFindingsCounts": {"standard": 1}
            },
            "verifiedFindings": {
                "projectionSnapshot": {
                    "verifiedQueue": [{"id": "finding-1"}],
                    "candidateQueue": []
                }
            }
        }));

        assert_eq!(derived["publishedFindingCount"].as_i64(), Some(0));
        assert_eq!(derived["hiddenFindingCount"].as_i64(), Some(1));
        assert_eq!(derived["pipelinePhase"].as_str(), Some("patch_preparation"));
    }
}
