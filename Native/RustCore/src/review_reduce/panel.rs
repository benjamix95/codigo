use super::panel_support::{
    build_file_ledger, build_phase_ledger, bundle_modes, severity_counts, sorted_ids,
    tool_executions,
};
use crate::review_pipeline::phases::{
    steps_completed, AUDIT, COMPLETED, DISCOVERY, PATCH_PREPARATION, PUBLISH_READY, QUEUED,
    VERIFICATION,
};
use crate::review_value::get_str;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

pub fn derive_review_panel_state(snapshot: Value) -> Value {
    let findings = array(&snapshot, "findings");
    let candidates = array(&snapshot, "candidates");
    let patches = array(&snapshot, "patches");
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
    let mut verified_ids = queue_ids(&verified_queue);
    if verified_ids.is_empty() {
        verified_ids = findings
            .iter()
            .filter(|finding| finding_is_verified(finding))
            .filter_map(|finding| get_str(finding, "id").map(ToString::to_string))
            .collect();
    }
    let publish_ready_ids = publish_ready_ids(&findings, &patches, &verified_ids);
    let verified_only_ids = verified_ids
        .iter()
        .filter(|id| !publish_ready_ids.contains(*id))
        .cloned()
        .collect::<Vec<_>>();
    let live_candidate_ids = candidate_queue
        .iter()
        .filter_map(|item| get_str(item, "id").map(ToString::to_string))
        .collect::<Vec<_>>();
    let pipeline_phase = pipeline_phase(&snapshot, &findings, &verified_ids, &publish_ready_ids);
    let phase_ledger = build_phase_ledger(&snapshot, &pipeline_phase);
    let file_ledger = build_file_ledger(&snapshot, &findings, &candidates, &patches);
    let published_severity_counts = severity_counts(&findings, &publish_ready_ids);
    let tools = tool_executions(&snapshot, &pipeline_phase);
    let candidate_count = live_candidate_ids.len() as i64;
    let verified_count = verified_ids.len() as i64;
    let publish_ready_count = publish_ready_ids.len() as i64;
    let visible_count = candidate_count + verified_count;
    let hidden_count = findings
        .len()
        .saturating_sub(publish_ready_count as usize + verified_only_ids.len())
        as i64;
    let terminal = matches!(
        get_str(&snapshot, "phase"),
        Some("completed") | Some("failed")
    );
    let findings_len = findings.len() as i64;
    let verification_gate_ready = verification_gate_ready_json(
        &snapshot,
        verified_count,
        publish_ready_count,
        findings_len,
    );
    let patch_gate_ready = patch_gate_ready_json(
        &snapshot,
        verified_count,
        publish_ready_count,
        findings_len,
    );

    json!({
        "liveCandidateIds": live_candidate_ids,
        "verifiedFindingIds": verified_only_ids,
        "publishReadyFindingIds": sorted_ids(&publish_ready_ids, &findings),
        "publishedFindingIds": sorted_ids(&publish_ready_ids, &findings),
        "publishedSeverityCounts": published_severity_counts,
        "pipelinePhase": pipeline_phase,
        "progressPercent": progress_percent(&pipeline_phase, verified_count, publish_ready_count),
        "stepsCompleted": steps_completed(&pipeline_phase),
        "stepsTotal": 6,
        "toolsTotal": tools.len(),
        "toolsCompleted": tools.iter().filter(|tool| tool["status"] == "completed").count(),
        "toolsRunning": tools.iter().filter(|tool| tool["status"] == "running").count(),
        "candidateCount": candidate_count,
        "verifiedCount": verified_count,
        "publishedFindingCount": publish_ready_count,
        "hiddenFindingCount": hidden_count.max(0),
        "verificationGateReady": verification_gate_ready,
        "patchGateReady": patch_gate_ready,
        "bundleModes": bundle_modes(&snapshot),
        "toolExecutions": tools,
        "isTerminal": terminal && pipeline_phase == COMPLETED,
        "warmState": if visible_count == 0 && !terminal { "warming" } else { "ready" },
        "emptyStateTitle": empty_title(visible_count, publish_ready_count, &pipeline_phase),
        "emptyStateSubtitle": empty_subtitle(candidate_count, verified_count, publish_ready_count, terminal),
        "phaseLedger": phase_ledger,
        "fileLedger": file_ledger
    })
}

/// Allinea le gate allo Swift: durante analyzing/fixing/testing non sono “verde” solo perché non ci sono finding ancora.
fn review_phase_is_active(snapshot: &Value) -> bool {
    matches!(
        get_str(snapshot, "phase"),
        Some("analyzing") | Some("fixing") | Some("testing") | Some("re_reviewing")
    )
}

fn verification_gate_ready_json(
    snapshot: &Value,
    verified_count: i64,
    _publish_ready_count: i64,
    findings_len: i64,
) -> bool {
    if verified_count > 0 {
        return true;
    }
    if get_str(snapshot, "phase") == Some("completed") {
        return true;
    }
    if review_phase_is_active(snapshot) {
        return false;
    }
    if get_str(snapshot, "phase") == Some("failed") {
        return findings_len == 0;
    }
    findings_len == 0
}

fn patch_gate_ready_json(
    snapshot: &Value,
    verified_count: i64,
    publish_ready_count: i64,
    findings_len: i64,
) -> bool {
    if verified_count > 0 {
        return verified_count == publish_ready_count;
    }
    if get_str(snapshot, "phase") == Some("completed") {
        return true;
    }
    if review_phase_is_active(snapshot) {
        return false;
    }
    if get_str(snapshot, "phase") == Some("failed") {
        return findings_len == 0;
    }
    findings_len == 0
}

fn array(snapshot: &Value, key: &str) -> Vec<Value> {
    snapshot
        .get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn queue_ids(queue: &[Value]) -> Vec<String> {
    queue
        .iter()
        .filter_map(|item| get_str(item, "id").map(ToString::to_string))
        .collect()
}

fn publish_ready_ids(
    findings: &[Value],
    patches: &[Value],
    verified_ids: &[String],
) -> HashSet<String> {
    let patch_by_finding = patches
        .iter()
        .filter_map(|patch| get_str(patch, "findingId").map(|id| (id.to_string(), patch)))
        .collect::<HashMap<_, _>>();

    findings
        .iter()
        .filter_map(|finding| {
            let finding_id = get_str(finding, "id")?;
            if !verified_ids.iter().any(|id| id == finding_id) || !finding_is_verified(finding) {
                return None;
            }
            let patch = patch_by_finding.get(finding_id)?;
            let patch_id = get_str(finding, "patchArtifactId")?;
            let patch_status = get_str(patch, "status")?;
            let verify_status = get_str(patch, "verifyStatus")?;
            (get_str(patch, "id") == Some(patch_id)
                && verify_status == "verified"
                && matches!(patch_status, "verified" | "applied" | "prOpened" | "merged"))
            .then(|| finding_id.to_string())
        })
        .collect()
}

fn pipeline_phase(
    snapshot: &Value,
    findings: &[Value],
    verified_ids: &[String],
    publish_ready_ids: &HashSet<String>,
) -> String {
    let terminal = matches!(
        get_str(snapshot, "phase"),
        Some("completed") | Some("failed")
    );
    let verified_total = if verified_ids.is_empty() {
        findings
            .iter()
            .filter(|finding| finding_is_verified(finding))
            .count()
    } else {
        verified_ids.len()
    };
    if terminal && (verified_total == 0 || publish_ready_ids.len() == verified_total) {
        return COMPLETED.to_string();
    }
    if !publish_ready_ids.is_empty() {
        return PUBLISH_READY.to_string();
    }
    if !verified_ids.is_empty() {
        return PATCH_PREPARATION.to_string();
    }
    if snapshot.get("analysisCompletedAt").is_some()
        || !findings.is_empty()
        || !array(snapshot, "candidates").is_empty()
    {
        return VERIFICATION.to_string();
    }
    let tool_count = snapshot
        .pointer("/audit/toolCoverage")
        .and_then(Value::as_object)
        .map(|items| items.len())
        .unwrap_or(0);
    if tool_count > 0 {
        return AUDIT.to_string();
    }
    if snapshot.get("startedAt").is_some()
        || matches!(
            get_str(snapshot, "phase"),
            Some("analyzing") | Some("fixing") | Some("testing") | Some("re_reviewing")
        )
    {
        return DISCOVERY.to_string();
    }
    QUEUED.to_string()
}

fn progress_percent(pipeline_phase: &str, verified_count: i64, publish_ready_count: i64) -> i64 {
    match pipeline_phase {
        COMPLETED => 100,
        PUBLISH_READY => 92,
        PATCH_PREPARATION => {
            65 + ((publish_ready_count as f64 / (verified_count.max(1) as f64)) * 20.0) as i64
        }
        VERIFICATION => 45,
        AUDIT => 25,
        DISCOVERY => 4,
        _ => 0,
    }
}

fn empty_title(visible_count: i64, publish_ready_count: i64, pipeline_phase: &str) -> &'static str {
    if visible_count > 0 || publish_ready_count > 0 {
        "Findings in progress"
    } else if pipeline_phase == QUEUED {
        "No findings yet"
    } else {
        "Waiting for review evidence"
    }
}

fn empty_subtitle(
    candidate_count: i64,
    verified_count: i64,
    publish_ready_count: i64,
    terminal: bool,
) -> &'static str {
    if publish_ready_count > 0 {
        "I finding publish-ready hanno patch e azioni già disponibili."
    } else if verified_count > 0 {
        "I finding verificati sono visibili anche se la patch finale è ancora in preparazione."
    } else if candidate_count > 0 {
        "I candidati live sono visibili mentre la verifica è ancora in corso."
    } else if terminal {
        "Il run si è chiuso senza finding verificati o publish-ready."
    } else {
        "La pipeline sta ancora raccogliendo evidenze e assegnando file."
    }
}

fn finding_is_verified(finding: &Value) -> bool {
    !finding.get("verifiedAt").unwrap_or(&Value::Null).is_null()
        || !finding
            .get("verificationReport")
            .unwrap_or(&Value::Null)
            .is_null()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn derive_review_panel_state_exposes_progressive_buckets() {
        let derived = derive_review_panel_state(json!({
            "phase": "completed",
            "startedAt": "2026-03-11T12:00:00Z",
            "completedAt": "2026-03-11T12:00:09Z",
            "scope": { "files": ["Sources/A.swift", "Sources/B.swift"] },
            "activeWorkerCount": 1,
            "analysisCompletedAt": "2026-03-11T12:00:05Z",
            "candidates": [{ "id": "candidate-1", "filePath": "Sources/A.swift", "severity": "warning" }],
            "findings": [{
                "id": "finding-1",
                "filePath": "Sources/B.swift",
                "severity": "critical",
                "verifiedAt": "2026-03-11T12:00:06Z",
                "verificationReport": "verified",
                "patchArtifactId": "patch-1"
            }],
            "patches": [{
                "id": "patch-1",
                "findingId": "finding-1",
                "status": "verified",
                "verifyStatus": "verified",
                "touchedFiles": ["Sources/B.swift"]
            }],
            "audit": {
                "toolCoverage": {"standard": true},
                "toolFindingsCounts": {"standard": 1}
            },
            "verifiedFindings": {
                "projectionSnapshot": {
                    "verifiedQueue": [{"id": "finding-1"}],
                    "candidateQueue": [{"id": "candidate-1"}]
                }
            }
        }));

        assert_eq!(
            derived["liveCandidateIds"]
                .as_array()
                .map(|items| items.len()),
            Some(1)
        );
        assert_eq!(
            derived["publishReadyFindingIds"]
                .as_array()
                .map(|items| items.len()),
            Some(1)
        );
        assert_eq!(derived["pipelinePhase"].as_str(), Some("completed"));
        assert_eq!(derived["stepsCompleted"].as_i64(), Some(6));
    }
}
