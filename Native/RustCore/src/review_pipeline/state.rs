use super::models::{ReviewPipelineConfig, ReviewPipelineScope, ReviewPipelineSnapshot, ReviewPipelineStep, ReviewTask};
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
pub struct PipelineSession {
    pub snapshot: ReviewPipelineSnapshot,
    pub clean_prompt: String,
    pub against_ref: Option<String>,
    pub resolved_scope: String,
    pub current_tasks: Vec<ReviewTask>,
    pub last_extraction_failure: Option<String>,
    pub step: ReviewPipelineStep,
}

impl PipelineSession {
    pub fn new(
        session_id: String,
        conversation_id: Option<String>,
        workspace_path: String,
        config: ReviewPipelineConfig,
        clean_prompt: String,
        against_ref: Option<String>,
        resolved_scope: String,
    ) -> Self {
        let now = apple_reference_seconds();
        let snapshot = ReviewPipelineSnapshot {
            session_id: session_id.clone(),
            conversation_id,
            mutation_sequence: 1,
            phase: "analyzing".to_string(),
            stage: "analysis".to_string(),
            findings: Vec::new(),
            candidates: Vec::new(),
            patches: Vec::new(),
            events: vec![session_started_event(&resolved_scope, 0, &session_id, 1, now)],
            config: config.clone(),
            scope: None,
            workspace_path: Some(workspace_path),
            current_round: 0,
            active_worker_count: 0,
            started_at: Some(now),
            completed_at: None,
            analysis_completed_at: None,
            last_error: None,
            current_job_id: None,
            last_test_status: None,
            audit: json!({
                "toolCoverage": {},
                "toolDurationsMs": {},
                "toolFindingsCounts": {},
                "toolAdapters": {}
            }),
            outcome: empty_outcome(),
            verified_findings: None,
            last_updated_at: now,
        };
        let step = ReviewPipelineStep::resolve_scope_files(clean_prompt.clone(), resolved_scope.clone(), against_ref.clone());
        Self {
            snapshot,
            clean_prompt,
            against_ref,
            resolved_scope,
            current_tasks: Vec::new(),
            last_extraction_failure: None,
            step,
        }
    }

    pub fn bump(&mut self) {
        self.snapshot.mutation_sequence += 1;
        self.snapshot.last_updated_at = apple_reference_seconds();
    }
}

pub fn set_scope(session: &mut PipelineSession, files: Vec<String>) {
    session.snapshot.scope = Some(ReviewPipelineScope {
        r#type: if session.against_ref.is_some() { "against_ref".to_string() } else { session.resolved_scope.clone() },
        files: files.clone(),
        r#ref: session.against_ref.clone(),
    });
    if let Some(first) = session.snapshot.events.first_mut() {
        if let Some(metadata) = first.get_mut("metadata").and_then(Value::as_object_mut) {
            metadata.insert("file_count".to_string(), json!(files.len().to_string()));
        }
    }
    session.bump();
}

pub fn append_events(session: &mut PipelineSession, events: &[Value]) {
    if !events.is_empty() {
        session.snapshot.events.extend(events.iter().cloned());
        session.bump();
    }
}

pub fn upsert_findings(session: &mut PipelineSession, findings: &[Value]) {
    upsert_by_id(&mut session.snapshot.findings, findings);
    refresh_outcome(session);
}

pub fn upsert_candidates(session: &mut PipelineSession, candidates: &[Value]) {
    upsert_by_id(&mut session.snapshot.candidates, candidates);
    refresh_outcome(session);
}

pub fn replace_open_findings_in_files(session: &mut PipelineSession, files: &[String]) {
    let file_set: std::collections::HashSet<String> = files.iter().cloned().collect();
    session.snapshot.findings.retain(|finding| {
        let status = finding.get("status").and_then(Value::as_str).unwrap_or("open");
        let path = finding.get("filePath").and_then(Value::as_str).unwrap_or("");
        !(is_open_status(status) && file_set.contains(path))
    });
    refresh_outcome(session);
}

pub fn mark_open_findings_fix_applied(session: &mut PipelineSession, files: &[String]) {
    let file_set: std::collections::HashSet<String> = files.iter().cloned().collect();
    for finding in &mut session.snapshot.findings {
        let path = finding.get("filePath").and_then(Value::as_str).unwrap_or("");
        let status = finding.get("status").and_then(Value::as_str).unwrap_or("open");
        if file_set.contains(path) && is_open_status(status) {
            if let Some(object) = finding.as_object_mut() {
                object.insert("status".to_string(), json!("patch_applied"));
            }
        }
    }
    refresh_outcome(session);
}

pub fn has_blocking_open_findings(session: &PipelineSession) -> bool {
    session.snapshot.findings.iter().any(|finding| {
        finding.get("blocking").and_then(Value::as_bool).unwrap_or(false)
            && is_open_status(finding.get("status").and_then(Value::as_str).unwrap_or("open"))
    })
}

pub fn complete(session: &mut PipelineSession, message: Option<String>) {
    session.snapshot.phase = "completed".to_string();
    session.snapshot.stage = "completed".to_string();
    session.snapshot.completed_at = Some(apple_reference_seconds());
    session.snapshot.active_worker_count = 0;
    session.snapshot.current_job_id = None;
    session.snapshot.last_error = None;
    session.snapshot.outcome = build_outcome(session, message.unwrap_or_else(|| format!("Review completed with {} findings", session.snapshot.findings.len())));
    session.bump();
}

pub fn fail(session: &mut PipelineSession, reason: String) {
    session.snapshot.phase = "failed".to_string();
    session.snapshot.stage = "failed".to_string();
    session.snapshot.completed_at = Some(apple_reference_seconds());
    session.snapshot.active_worker_count = 0;
    session.snapshot.current_job_id = None;
    session.snapshot.last_error = Some(reason.clone());
    session.snapshot.outcome = build_outcome(session, format!("Review failed: {reason}"));
    session.bump();
}

pub fn analysis_completed(session: &mut PipelineSession) {
    session.snapshot.analysis_completed_at = Some(apple_reference_seconds());
    session.snapshot.stage = "findings".to_string();
    session.bump();
}

fn upsert_by_id(target: &mut Vec<Value>, incoming: &[Value]) {
    for value in incoming {
        let Some(id) = value.get("id").and_then(Value::as_str) else { continue };
        if let Some(index) = target.iter().position(|item| item.get("id").and_then(Value::as_str) == Some(id)) {
            target[index] = value.clone();
        } else {
            target.push(value.clone());
        }
    }
}

fn refresh_outcome(session: &mut PipelineSession) {
    session.snapshot.outcome = build_outcome(session, format!("{} verified finding(s), {} false positive(s), 0 patch(es) applied.", session.snapshot.findings.len(), false_positive_count(&session.snapshot.candidates)));
    session.bump();
}

fn build_outcome(session: &PipelineSession, summary: String) -> Value {
    json!({
        "summary": summary,
        "verifiedFindings": session.snapshot.findings.len(),
        "falsePositives": false_positive_count(&session.snapshot.candidates),
        "patchesReady": 0,
        "patchesApplied": 0,
        "prsOpened": 0,
        "mergedPatches": 0,
        "conflictsDetected": 0,
        "manualActionRequired": session.snapshot.candidates.iter().any(|item| item.get("verificationStatus").and_then(Value::as_str) == Some("inconclusive")),
        "testsStatus": session.snapshot.last_test_status,
        "generatedAt": apple_reference_seconds(),
    })
}

fn false_positive_count(candidates: &[Value]) -> usize {
    candidates
        .iter()
        .filter(|item| item.get("verificationStatus").and_then(Value::as_str) == Some("rejected_false_positive"))
        .count()
}

fn empty_outcome() -> Value {
    json!({
        "summary": "No review outcome available yet.",
        "verifiedFindings": 0,
        "falsePositives": 0,
        "patchesReady": 0,
        "patchesApplied": 0,
        "prsOpened": 0,
        "mergedPatches": 0,
        "conflictsDetected": 0,
        "manualActionRequired": false,
        "testsStatus": Value::Null,
        "generatedAt": -978307200.0,
    })
}

fn session_started_event(scope: &str, file_count: usize, session_id: &str, sequence: u64, now: f64) -> Value {
    json!({
        "id": format!("{session_id}-evt-{sequence}"),
        "type": "session_started",
        "timestamp": now,
        "detail": format!("Review started with scope: {scope}"),
        "metadata": {
            "scope": scope,
            "file_count": file_count.to_string()
        }
    })
}

fn is_open_status(status: &str) -> bool {
    matches!(status, "open" | "patch_preparing" | "patch_ready" | "patch_applying" | "patch_failed" | "pr_opened" | "blocked")
}

pub fn apple_reference_seconds() -> f64 {
    let unix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs_f64())
        .unwrap_or(0.0);
    unix - 978_307_200.0
}
