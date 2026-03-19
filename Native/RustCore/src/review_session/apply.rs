use super::helpers::{array, array_mut, build_outcome, event, is_open_status, now_reference_seconds, scope_description};
use super::models::{ReviewRegistryActionRequest, ReviewSessionActionRequest, ReviewSessionResponse};
use crate::review_command::models::ReviewCommandMutationRequest;
use crate::review_command::mutator::mutate_snapshot;
use serde_json::{json, Value};
use std::collections::HashMap;

pub fn apply_registry_action(request: ReviewRegistryActionRequest) -> ReviewSessionResponse {
    let snapshot_input = request.snapshot.clone();
    let mutation = mutate_snapshot(ReviewCommandMutationRequest {
        schema_version: 1,
        action: request.operation,
        snapshot: snapshot_input,
        payload: request.payload,
    });
    if mutation.is_error {
        return ReviewSessionResponse::error("registry_mutation_failed", mutation.message.as_deref().unwrap_or("registry mutation failed"));
    }
    let mut snapshot = mutation_configured_snapshot(mutation, request.snapshot);
    snapshot["outcome"] = build_outcome(&snapshot, None);
    ReviewSessionResponse::success(snapshot)
}

pub fn apply_action(request: ReviewSessionActionRequest) -> ReviewSessionResponse {
    let mut snapshot = request.snapshot.clone();
    let now = now_reference_seconds();
    let result = match request.operation.as_str() {
        "start" => start(&mut snapshot, &request, now),
        "complete" => complete(&mut snapshot, now),
        "fail" => fail(&mut snapshot, request.error.as_deref().unwrap_or("unknown error"), now),
        "reset" => reset(&mut snapshot, now),
        "set_phase" => set_string(&mut snapshot, "phase", request.phase.as_deref()),
        "set_stage" => set_string(&mut snapshot, "stage", request.stage.as_deref()),
        "set_current_job_id" => set_optional_string(&mut snapshot, "currentJobId", request.job_id),
        "mark_analysis_started" => mark_simple(&mut snapshot, "analyzing", "analysis", "analysis_started", "Analysis started", now),
        "mark_analysis_completed" => mark_analysis_completed(&mut snapshot, now),
        "mark_audit_started" => mark_audit_started(&mut snapshot, request.tool_name.as_deref(), now),
        "record_audit_result" => record_audit_result(&mut snapshot, request.audit_result, now),
        "start_round" => start_round(&mut snapshot, request.round.unwrap_or(0), now),
        "set_active_worker_count" => set_number(&mut snapshot, "activeWorkerCount", request.count.unwrap_or(0)),
        "mark_worker_spawned" => mark_worker(&mut snapshot, "worker_spawned", request.worker_id, request.title, now),
        "mark_worker_completed" => mark_worker(&mut snapshot, "worker_completed", request.worker_id, request.title, now),
        "mark_round_completed" => mark_round_completed(&mut snapshot, request.round.unwrap_or(0), now),
        "mark_testing_started" => mark_simple(&mut snapshot, "testing", "testing", "", "", now),
        "mark_test_result" => mark_test_result(&mut snapshot, request.test_status.as_deref(), request.result_detail.as_deref(), now),
        "mark_re_review_started" => mark_re_review_started(&mut snapshot, request.round.unwrap_or(0), now),
        "add_finding" => add_findings(&mut snapshot, request.finding.into_iter().collect(), now),
        "add_findings" => add_findings(&mut snapshot, request.findings.unwrap_or_default(), now),
        "add_candidate" => add_candidates(&mut snapshot, request.candidate.into_iter().collect(), now),
        "add_candidates" => add_candidates(&mut snapshot, request.candidates.unwrap_or_default(), now),
        "update_candidate_status" => update_candidate_status(&mut snapshot, &request, now),
        "promote_candidate_to_finding" => promote_candidate_to_finding(&mut snapshot, request.candidate_id.as_deref(), now),
        "replace_open_findings" => replace_open_findings(&mut snapshot, request.files, request.findings.unwrap_or_default(), now),
        "apply_fix" | "dismiss" | "comment" | "configure" | "close_finding" | "upsert_patch" => {
            let payload = command_payload(&request);
            return apply_registry_action(ReviewRegistryActionRequest {
                schema_version: 1,
                operation: request.operation,
                snapshot,
                payload,
            });
        }
        "mark_all_open_findings_as_fix_applied" => mark_open_findings(&mut snapshot, None),
        "mark_open_findings_as_fix_applied" => mark_open_findings(&mut snapshot, request.files),
        _ => Err(format!("Unsupported review session operation: {}", request.operation)),
    };
    if let Err(message) = result {
        return ReviewSessionResponse::error("invalid_operation", &message);
    }
    snapshot["mutationSequence"] = json!(snapshot.get("mutationSequence").and_then(Value::as_u64).unwrap_or(0) + 1);
    snapshot["lastUpdatedAt"] = json!(now);
    snapshot["outcome"] = build_outcome(&snapshot, None);
    ReviewSessionResponse::success(snapshot)
}

fn start(snapshot: &mut Value, request: &ReviewSessionActionRequest, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("analyzing");
    snapshot["stage"] = json!("analysis");
    snapshot["scope"] = request.scope.clone().unwrap_or(Value::Null);
    snapshot["workspacePath"] = request.workspace_path.clone().map(Value::String).unwrap_or(Value::Null);
    snapshot["findings"] = json!([]);
    snapshot["candidates"] = json!([]);
    snapshot["patches"] = json!([]);
    snapshot["events"] = json!([event("session_started", Some(format!("Review started with scope: {}", scope_description(snapshot.get("scope").unwrap_or(&Value::Null)))), json!({"scope": scope_description(snapshot.get("scope").unwrap_or(&Value::Null)), "file_count": snapshot.get("scope").and_then(|v| v.get("files")).and_then(Value::as_array).map(|a| a.len()).unwrap_or(0).to_string()}), now)]);
    snapshot["currentRound"] = json!(0);
    snapshot["activeWorkerCount"] = json!(0);
    snapshot["startedAt"] = json!(now);
    snapshot["completedAt"] = Value::Null;
    snapshot["analysisCompletedAt"] = Value::Null;
    snapshot["lastError"] = Value::Null;
    snapshot["currentJobId"] = Value::Null;
    snapshot["lastTestStatus"] = Value::Null;
    snapshot["audit"] = json!({"toolCoverage": {}, "toolDurationsMs": {}, "toolFindingsCounts": {}, "toolAdapters": {}});
    snapshot["phaseLedger"] = json!([]);
    snapshot["fileLedger"] = json!([]);
    Ok(())
}

fn complete(snapshot: &mut Value, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("completed");
    snapshot["stage"] = json!("completed");
    snapshot["completedAt"] = json!(now);
    snapshot["activeWorkerCount"] = json!(0);
    snapshot["currentJobId"] = Value::Null;
    let findings_count = array(snapshot, "findings")?.len();
    array_mut(snapshot, "events")?.push(event("session_completed", Some(format!("Review completed with {} findings", findings_count)), json!({}), now));
    Ok(())
}

fn fail(snapshot: &mut Value, message: &str, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("failed");
    snapshot["stage"] = json!("failed");
    snapshot["lastError"] = json!(message);
    snapshot["completedAt"] = json!(now);
    snapshot["activeWorkerCount"] = json!(0);
    snapshot["currentJobId"] = Value::Null;
    array_mut(snapshot, "events")?.push(event("error", Some(message.to_string()), json!({}), now));
    snapshot["outcome"] = build_outcome(snapshot, Some(format!("Review failed: {message}")));
    Ok(())
}

fn reset(snapshot: &mut Value, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("idle");
    snapshot["stage"] = json!("idle");
    snapshot["findings"] = json!([]);
    snapshot["candidates"] = json!([]);
    snapshot["patches"] = json!([]);
    snapshot["events"] = json!([]);
    snapshot["scope"] = Value::Null;
    snapshot["workspacePath"] = Value::Null;
    snapshot["currentRound"] = json!(0);
    snapshot["activeWorkerCount"] = json!(0);
    snapshot["startedAt"] = Value::Null;
    snapshot["completedAt"] = Value::Null;
    snapshot["analysisCompletedAt"] = Value::Null;
    snapshot["lastError"] = Value::Null;
    snapshot["currentJobId"] = Value::Null;
    snapshot["lastTestStatus"] = Value::Null;
    snapshot["audit"] = json!({"toolCoverage": {}, "toolDurationsMs": {}, "toolFindingsCounts": {}, "toolAdapters": {}});
    snapshot["outcome"] = build_outcome(snapshot, None);
    snapshot["phaseLedger"] = json!([]);
    snapshot["fileLedger"] = json!([]);
    snapshot["lastUpdatedAt"] = json!(now);
    Ok(())
}

fn mark_simple(snapshot: &mut Value, phase: &str, stage: &str, event_type: &str, detail: &str, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!(phase);
    snapshot["stage"] = json!(stage);
    if !event_type.is_empty() {
        array_mut(snapshot, "events")?.push(event(event_type, Some(detail.to_string()), json!({}), now));
    }
    Ok(())
}

fn mark_analysis_completed(snapshot: &mut Value, now: f64) -> Result<(), String> {
    snapshot["analysisCompletedAt"] = json!(now);
    snapshot["stage"] = json!("findings");
    array_mut(snapshot, "events")?.push(event("analysis_completed", Some("Analysis completed".to_string()), json!({}), now));
    Ok(())
}

fn mark_audit_started(snapshot: &mut Value, tool_name: Option<&str>, now: f64) -> Result<(), String> {
    let tool_name = tool_name.unwrap_or_default();
    array_mut(snapshot, "events")?.push(event("audit_started", Some(format!("Running {tool_name}")), json!({"tool": tool_name}), now));
    Ok(())
}

fn record_audit_result(snapshot: &mut Value, audit_result: Option<Value>, now: f64) -> Result<(), String> {
    let Some(result) = audit_result else {
        return Err("auditResult is required".to_string());
    };
    let tool_name = result.get("toolName").and_then(Value::as_str).unwrap_or_default();
    let coverage = result.get("coverageAvailable").and_then(Value::as_bool).unwrap_or(false);
    let duration_ms = result.get("durationMs").and_then(Value::as_i64).unwrap_or(0);
    let findings_count = result.get("findings").and_then(Value::as_array).map(|items| items.len()).unwrap_or(0);
    let adapters_used = result.get("adaptersUsed").and_then(Value::as_array).cloned().unwrap_or_default();
    let summary = result.get("summary").and_then(Value::as_str).unwrap_or_default();

    if let Some(audit) = snapshot.get_mut("audit").and_then(Value::as_object_mut) {
        audit.entry("toolCoverage".to_string()).or_insert_with(|| json!({}))[tool_name] = json!(coverage);
        audit.entry("toolDurationsMs".to_string()).or_insert_with(|| json!({}))[tool_name] = json!(duration_ms);
        audit.entry("toolFindingsCounts".to_string()).or_insert_with(|| json!({}))[tool_name] = json!(findings_count);
        audit.entry("toolAdapters".to_string()).or_insert_with(|| json!({}))[tool_name] = Value::Array(adapters_used);
    }

    array_mut(snapshot, "events")?.push(event(
        "audit_completed",
        Some(summary.to_string()),
        json!({
            "tool": tool_name,
            "coverage": if coverage { "true" } else { "false" },
            "duration_ms": duration_ms.to_string(),
            "findings_count": findings_count.to_string(),
        }),
        now,
    ));
    Ok(())
}

fn start_round(snapshot: &mut Value, round: i64, now: f64) -> Result<(), String> {
    snapshot["currentRound"] = json!(round);
    snapshot["phase"] = json!("fixing");
    snapshot["stage"] = json!("fixing");
    let max_rounds = snapshot.get("config").and_then(|v| v.get("maxRounds")).and_then(Value::as_i64).unwrap_or(3);
    array_mut(snapshot, "events")?.push(event("round_started", Some(format!("Round {round}/{max_rounds}")), json!({"round": round.to_string(), "max_rounds": max_rounds.to_string()}), now));
    Ok(())
}

fn mark_worker(snapshot: &mut Value, kind: &str, worker_id: Option<String>, title: Option<String>, now: f64) -> Result<(), String> {
    array_mut(snapshot, "events")?.push(event(kind, title, json!({"worker_id": worker_id.unwrap_or_default()}), now));
    Ok(())
}

fn mark_round_completed(snapshot: &mut Value, round: i64, now: f64) -> Result<(), String> {
    array_mut(snapshot, "events")?.push(event("round_completed", Some(format!("Round {round} completed")), json!({"round": round.to_string()}), now));
    Ok(())
}

fn mark_test_result(snapshot: &mut Value, status: Option<&str>, detail: Option<&str>, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("testing");
    snapshot["stage"] = json!("testing");
    let status = status.unwrap_or("inconclusive");
    snapshot["lastTestStatus"] = json!(status);
    let event_type = if status == "passed" { "tests_passed" } else { "tests_failed" };
    array_mut(snapshot, "events")?.push(event(event_type, Some(detail.unwrap_or_default().to_string()), json!({}), now));
    Ok(())
}

fn mark_re_review_started(snapshot: &mut Value, round: i64, now: f64) -> Result<(), String> {
    snapshot["phase"] = json!("re_reviewing");
    snapshot["stage"] = json!("reReview");
    array_mut(snapshot, "events")?.push(event(
        "analysis_started",
        Some(format!("Re-review round {round} started")),
        json!({"round": round.to_string(), "stage": "re_review"}),
        now,
    ));
    Ok(())
}

fn add_findings(snapshot: &mut Value, new_findings: Vec<Value>, now: f64) -> Result<(), String> {
    for finding in new_findings {
        let id = finding.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
        let severity = finding.get("severity").and_then(Value::as_str).unwrap_or_default().to_string();
        let file_path = finding.get("filePath").and_then(Value::as_str).unwrap_or("unknown").to_string();
        array_mut(snapshot, "findings")?.push(finding);
        array_mut(snapshot, "events")?.push(event("finding_added", Some(format!("[{severity}] {file_path}")), json!({"finding_id": id, "severity": severity, "file_path": file_path}), now));
    }
    Ok(())
}

fn add_candidates(snapshot: &mut Value, new_candidates: Vec<Value>, now: f64) -> Result<(), String> {
    for candidate in new_candidates {
        let id = candidate.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
        let file_path = candidate.get("filePath").and_then(Value::as_str).unwrap_or("unknown").to_string();
        array_mut(snapshot, "candidates")?.push(candidate);
        array_mut(snapshot, "events")?.push(event("candidate_added", Some(file_path.clone()), json!({"candidate_id": id, "file_path": file_path}), now));
    }
    Ok(())
}

fn update_candidate_status(snapshot: &mut Value, request: &ReviewSessionActionRequest, now: f64) -> Result<(), String> {
    let candidate_id = request.candidate_id.as_deref().ok_or_else(|| "candidateId is required".to_string())?;
    let status = request.status.as_deref().unwrap_or("new");
    let mut event_value: Option<Value> = None;
    if let Some(candidates) = snapshot.get_mut("candidates").and_then(Value::as_array_mut) {
        let Some(candidate) = candidates.iter_mut().find(|item| item.get("id").and_then(Value::as_str) == Some(candidate_id)) else {
            return Ok(());
        };
        candidate["verificationStatus"] = json!(status);
        candidate["verificationMethod"] = request.method.clone().map(Value::String).unwrap_or(Value::Null);
        candidate["verificationReport"] = request.report.clone().map(Value::String).unwrap_or(Value::Null);
        candidate["falsePositiveReason"] = request.false_positive_reason.clone().map(Value::String).unwrap_or(Value::Null);
        candidate["verifiedAt"] = if status == "verified" { json!(now) } else { Value::Null };
        event_value = match status {
            "verified" => Some(event("candidate_verified", Some(format!("Candidate {candidate_id} verified")), json!({"candidate_id": candidate_id}), now)),
            "rejected_false_positive" => Some(event("candidate_rejected", Some(format!("Candidate {candidate_id} rejected")), json!({"candidate_id": candidate_id, "reason": request.false_positive_reason.clone().unwrap_or_else(|| "false_positive".to_string())}), now)),
            _ => None,
        };
    }
    if let Some(event_value) = event_value {
        array_mut(snapshot, "events")?.push(event_value);
    }
    Ok(())
}

fn promote_candidate_to_finding(snapshot: &mut Value, candidate_id: Option<&str>, now: f64) -> Result<(), String> {
    let candidate_id = candidate_id.ok_or_else(|| "candidateId is required".to_string())?;
    let candidates = array(snapshot, "candidates")?;
    let Some(candidate) = candidates.iter().find(|item| item.get("id").and_then(Value::as_str) == Some(candidate_id)) else {
        return Ok(());
    };
    if candidate.get("verificationStatus").and_then(Value::as_str) != Some("verified") {
        return Ok(());
    }
    if array(snapshot, "findings")?.iter().any(|item| item.get("id").and_then(Value::as_str) == Some(candidate_id)) {
        return Ok(());
    }
    let finding = json!({
        "id": candidate.get("id").cloned().unwrap_or(Value::Null),
        "severity": candidate.get("severity").cloned().unwrap_or(Value::Null),
        "category": candidate.get("category").cloned().unwrap_or(Value::Null),
        "origin": candidate.get("origin").cloned().unwrap_or_else(|| json!("reviewer")),
        "filePath": candidate.get("filePath").cloned().unwrap_or(Value::Null),
        "lineNumber": candidate.get("lineNumber").cloned().unwrap_or(Value::Null),
        "endLineNumber": candidate.get("endLineNumber").cloned().unwrap_or(Value::Null),
        "message": candidate.get("message").cloned().unwrap_or(Value::Null),
        "suggestedFix": candidate.get("reproOrReasoning").cloned().unwrap_or(Value::Null),
        "expectedInvariant": candidate.get("expectedInvariant").cloned().unwrap_or(Value::Null),
        "reproOrReasoning": candidate.get("reproOrReasoning").cloned().unwrap_or(Value::Null),
        "confidence": candidate.get("confidence").cloned().unwrap_or(Value::Null),
        "evidence": candidate.get("evidence").cloned().unwrap_or(Value::Null),
        "sourceTool": candidate.get("sourceTool").cloned().unwrap_or(Value::Null),
        "blocking": candidate.get("severity").and_then(Value::as_str) == Some("critical"),
        "status": "open",
        "verificationReport": candidate.get("verificationReport").cloned().unwrap_or(Value::Null),
        "verifiedAt": candidate.get("verifiedAt").cloned().unwrap_or(json!(now)),
        "verificationMethod": candidate.get("verificationMethod").cloned().unwrap_or(Value::Null),
        "falsePositiveReason": Value::Null,
        "patchArtifactId": Value::Null,
        "comments": [],
        "createdAt": candidate.get("createdAt").cloned().unwrap_or(json!(now)),
    });
    add_findings(snapshot, vec![finding], now)
}

fn replace_open_findings(snapshot: &mut Value, files: Option<Vec<String>>, new_findings: Vec<Value>, now: f64) -> Result<(), String> {
    let reviewed: Vec<String> = files.unwrap_or_else(|| {
        new_findings.iter().filter_map(|item| item.get("filePath").and_then(Value::as_str).map(ToString::to_string)).collect()
    });
    if let Some(findings) = snapshot.get_mut("findings").and_then(Value::as_array_mut) {
        findings.retain(|finding| {
            let file = finding.get("filePath").and_then(Value::as_str).unwrap_or_default();
            let status = finding.get("status").and_then(Value::as_str).unwrap_or("open");
            !(is_open_status(status) && reviewed.iter().any(|item| item == file))
        });
    }
    add_findings(snapshot, new_findings, now)
}

fn mark_open_findings(snapshot: &mut Value, files: Option<Vec<String>>) -> Result<(), String> {
    let mut changed_ids = Vec::new();
    if let Some(findings) = snapshot.get_mut("findings").and_then(Value::as_array_mut) {
        for finding in findings.iter_mut() {
            let file = finding.get("filePath").and_then(Value::as_str).unwrap_or_default();
            let status = finding.get("status").and_then(Value::as_str).unwrap_or("open");
            let should_mark = files.as_ref().map(|list| list.iter().any(|item| item == file)).unwrap_or(true);
            if should_mark && is_open_status(status) {
                let next = if files.is_some() { "patch_applied" } else { "fix_applied" };
                finding["status"] = json!(next);
                changed_ids.push(finding.get("id").and_then(Value::as_str).unwrap_or_default().to_string());
            }
        }
    }
    for finding_id in changed_ids {
        array_mut(snapshot, "events")?.push(event("finding_fix_applied", Some(format!("Fix applied for finding {finding_id}")), json!({"finding_id": finding_id}), now_reference_seconds()));
    }
    Ok(())
}

fn set_string(snapshot: &mut Value, key: &str, value: Option<&str>) -> Result<(), String> {
    snapshot[key] = value.map(|v| json!(v)).unwrap_or(Value::Null);
    Ok(())
}

fn set_optional_string(snapshot: &mut Value, key: &str, value: Option<String>) -> Result<(), String> {
    snapshot[key] = value.map(Value::String).unwrap_or(Value::Null);
    Ok(())
}

fn set_number(snapshot: &mut Value, key: &str, value: i64) -> Result<(), String> {
    snapshot[key] = json!(value);
    Ok(())
}

fn command_payload(request: &ReviewSessionActionRequest) -> HashMap<String, String> {
    let mut payload = HashMap::new();
    if let Some(finding_id) = &request.finding_id { payload.insert("finding_id".to_string(), finding_id.clone()); }
    if let Some(reason) = &request.reason { payload.insert("reason".to_string(), reason.clone()); }
    if let Some(comment) = &request.comment {
        if let Some(author) = comment.get("author").and_then(Value::as_str) { payload.insert("author".to_string(), author.to_string()); }
        if let Some(content) = comment.get("content").and_then(Value::as_str) { payload.insert("content".to_string(), content.to_string()); }
    }
    if let Some(config) = &request.config {
        for (lhs, rhs) in [("max_workers", "maxWorkers"), ("max_rounds", "maxRounds"), ("analysis_backend", "analysisBackend"), ("execution_backend", "executionBackend"), ("analysis_only", "analysisOnly")] {
            if let Some(value) = config.get(rhs) {
                let text = value.as_str().map(ToString::to_string)
                    .or_else(|| value.as_i64().map(|v| v.to_string()))
                    .or_else(|| value.as_bool().map(|v| if v { "true".into() } else { "false".into() }));
                if let Some(text) = text { payload.insert(lhs.to_string(), text); }
            }
        }
    }
    if let Some(patch) = &request.patch {
        payload.insert("patch_json".to_string(), patch.to_string());
    }
    payload
}

fn mutation_configured_snapshot(mutation: crate::review_command::models::ReviewCommandMutationResponse, mut snapshot: Value) -> Value {
    if let Some(findings) = mutation.findings { snapshot["findings"] = Value::Array(findings); }
    if let Some(patches) = mutation.patches { snapshot["patches"] = Value::Array(patches); }
    if let Some(events) = mutation.events { snapshot["events"] = Value::Array(events); }
    if let Some(config) = mutation.config { snapshot["config"] = serde_json::to_value(config).unwrap_or(Value::Null); }
    snapshot
}
