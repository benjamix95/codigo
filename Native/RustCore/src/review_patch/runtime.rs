use super::models::{
    ReviewPatchActionRequest, ReviewPatchRuntimeResponse, ReviewPatchRuntimeResultRequest,
    ReviewPatchRuntimeStartRequest, ReviewPatchRuntimeStateRequest,
};
use super::planner::handle_patch_action;
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

#[derive(Clone, Debug)]
struct ReviewPatchRuntimeSession {
    runtime_id: String,
    steps: Vec<String>,
    step_index: usize,
    status: RuntimeStatus,
    error_message: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum RuntimeStatus {
    Running,
    Completed,
    Failed,
}

static RUNTIMES: OnceLock<Mutex<HashMap<String, ReviewPatchRuntimeSession>>> = OnceLock::new();

pub fn start_runtime(request: ReviewPatchRuntimeStartRequest) -> ReviewPatchRuntimeResponse {
    let planning = handle_patch_action(ReviewPatchActionRequest {
        schema_version: request.schema_version,
        operation: "plan_execution".to_string(),
        action: request.action,
        session_id: request.session_id,
        finding_id: request.finding_id,
        conversation_id: request.conversation_id,
        snapshot: request.snapshot,
    });
    if planning.is_error {
        return ReviewPatchRuntimeResponse::err(
            planning.error_code.as_deref().unwrap_or("runtime_start_failed"),
            planning.error_message.as_deref().unwrap_or("failed to start patch runtime"),
        );
    }

    let runtime_id = format!("patch-runtime-{}", uuid_seed());
    let current_step = planning.steps.first().cloned();
    let status = if current_step.is_some() {
        RuntimeStatus::Running
    } else {
        RuntimeStatus::Completed
    };
    let session = ReviewPatchRuntimeSession {
        runtime_id: runtime_id.clone(),
        steps: planning.steps,
        step_index: 0,
        status: status.clone(),
        error_message: None,
    };
    store().lock().unwrap().insert(runtime_id.clone(), session);
    response_for(runtime_id, status, current_step, None)
}

pub fn apply_runtime_result(request: ReviewPatchRuntimeResultRequest) -> ReviewPatchRuntimeResponse {
    let mut runtimes = store().lock().unwrap();
    let Some(session) = runtimes.get_mut(&request.runtime_id) else {
        return ReviewPatchRuntimeResponse::err("runtime_not_found", "patch runtime session not found");
    };
    if session.status != RuntimeStatus::Running {
        return ReviewPatchRuntimeResponse::err("runtime_terminal", "patch runtime session is already terminal");
    }
    if !request.succeeded {
        session.status = RuntimeStatus::Failed;
        session.error_message = Some(request.error_message.unwrap_or_else(|| "patch step failed".to_string()));
        return response_for(
            session.runtime_id.clone(),
            RuntimeStatus::Failed,
            None,
            session.error_message.clone(),
        );
    }

    session.step_index += 1;
    if session.step_index >= session.steps.len() {
        session.status = RuntimeStatus::Completed;
        return response_for(session.runtime_id.clone(), RuntimeStatus::Completed, None, None);
    }
    let next_step = session.steps.get(session.step_index).cloned();
    response_for(session.runtime_id.clone(), RuntimeStatus::Running, next_step, None)
}

pub fn get_runtime_state(request: ReviewPatchRuntimeStateRequest) -> ReviewPatchRuntimeResponse {
    let runtimes = store().lock().unwrap();
    let Some(session) = runtimes.get(&request.runtime_id) else {
        return ReviewPatchRuntimeResponse::err("runtime_not_found", "patch runtime session not found");
    };
    let current_step = if session.status == RuntimeStatus::Running {
        session.steps.get(session.step_index).cloned()
    } else {
        None
    };
    response_for(
        session.runtime_id.clone(),
        session.status.clone(),
        current_step,
        session.error_message.clone(),
    )
}

fn response_for(
    runtime_id: String,
    status: RuntimeStatus,
    current_step: Option<String>,
    error_message: Option<String>,
) -> ReviewPatchRuntimeResponse {
    match status {
        RuntimeStatus::Running => ReviewPatchRuntimeResponse::ok(runtime_id, "running", current_step),
        RuntimeStatus::Completed => ReviewPatchRuntimeResponse::ok(runtime_id, "completed", None),
        RuntimeStatus::Failed => ReviewPatchRuntimeResponse {
            schema_version: 1,
            is_error: false,
            error_code: None,
            error_message,
            runtime_id: Some(runtime_id),
            status: "failed".to_string(),
            current_step: None,
        },
    }
}

fn store() -> &'static Mutex<HashMap<String, ReviewPatchRuntimeSession>> {
    RUNTIMES.get_or_init(|| Mutex::new(HashMap::new()))
}

fn uuid_seed() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{:x}", now)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_patch::models::{ReviewFindingRecord, ReviewPatchRecord, ReviewPatchSnapshot};

    fn snapshot() -> ReviewPatchSnapshot {
        ReviewPatchSnapshot {
            session_id: "s1".to_string(),
            conversation_id: None,
            finding_ids: vec!["f1".to_string()],
            candidate_ids: Vec::new(),
            patches: vec![ReviewPatchRecord {
                id: "p1".to_string(),
                finding_id: "f1".to_string(),
                status: "applied".to_string(),
                verify_status: "verified".to_string(),
                validation_status: "passed".to_string(),
                risk_score: 0.1,
            }],
            findings: vec![ReviewFindingRecord {
                id: "f1".to_string(),
                status: "patch_applied".to_string(),
                severity: "warning".to_string(),
                category: "correctness".to_string(),
                message: "m".to_string(),
                patch_artifact_id: Some("p1".to_string()),
            }],
        }
    }

    #[test]
    fn runtime_advances_until_completed() {
        let started = start_runtime(ReviewPatchRuntimeStartRequest {
            schema_version: 1,
            action: "apply_patch".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: snapshot(),
        });
        assert_eq!(started.status, "running");
        let runtime_id = started.runtime_id.unwrap();
        let finished = apply_runtime_result(ReviewPatchRuntimeResultRequest {
            schema_version: 1,
            runtime_id,
            succeeded: true,
            error_message: None,
        });
        assert_eq!(finished.status, "completed");
    }

    #[test]
    fn runtime_fails_on_failed_step() {
        let started = start_runtime(ReviewPatchRuntimeStartRequest {
            schema_version: 1,
            action: "close_finding".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: snapshot(),
        });
        let failed = apply_runtime_result(ReviewPatchRuntimeResultRequest {
            schema_version: 1,
            runtime_id: started.runtime_id.unwrap(),
            succeeded: false,
            error_message: Some("boom".to_string()),
        });
        assert_eq!(failed.status, "failed");
        assert_eq!(failed.error_message.as_deref(), Some("boom"));
    }

    #[test]
    fn runtime_rejects_double_terminal_transition() {
        let started = start_runtime(ReviewPatchRuntimeStartRequest {
            schema_version: 1,
            action: "close_finding".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: snapshot(),
        });
        let runtime_id = started.runtime_id.unwrap();
        let completed = apply_runtime_result(ReviewPatchRuntimeResultRequest {
            schema_version: 1,
            runtime_id: runtime_id.clone(),
            succeeded: true,
            error_message: None,
        });
        assert_eq!(completed.status, "completed");
        let terminal = apply_runtime_result(ReviewPatchRuntimeResultRequest {
            schema_version: 1,
            runtime_id,
            succeeded: true,
            error_message: None,
        });
        assert!(terminal.is_error);
    }
}
