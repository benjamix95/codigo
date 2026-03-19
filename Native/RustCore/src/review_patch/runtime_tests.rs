use super::models::{
    ReviewFindingRecord, ReviewPatchRecord, ReviewPatchRuntimeResultRequest,
    ReviewPatchRuntimeStartRequest, ReviewPatchRuntimeStateRequest, ReviewPatchSnapshot,
};
use super::runtime::{apply_runtime_result, get_runtime_state, start_runtime};

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
    assert_eq!(started.action.as_deref(), Some("apply_patch"));
    assert_eq!(started.session_id.as_deref(), Some("s1"));
    assert_eq!(started.finding_id.as_deref(), Some("f1"));
    assert_eq!(started.steps, vec!["apply_patch".to_string()]);
    assert!(started.completed_steps.is_empty());
    let runtime_id = started.runtime_id.unwrap();
    let finished = apply_runtime_result(ReviewPatchRuntimeResultRequest {
        schema_version: 1,
        runtime_id,
        succeeded: true,
        error_message: None,
    });
    assert_eq!(finished.status, "completed");
    assert_eq!(finished.completed_steps, vec!["apply_patch".to_string()]);
    assert_eq!(finished.terminal_reason.as_deref(), Some("completed"));
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
    assert_eq!(failed.terminal_reason.as_deref(), Some("step_failed"));
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

#[test]
fn runtime_state_reports_completed_steps_while_running() {
    let started = start_runtime(ReviewPatchRuntimeStartRequest {
        schema_version: 1,
        action: "apply_fix".to_string(),
        session_id: "s1".to_string(),
        finding_id: "f1".to_string(),
        conversation_id: None,
        snapshot: ReviewPatchSnapshot {
            session_id: "s1".to_string(),
            conversation_id: None,
            finding_ids: vec!["f1".to_string()],
            candidate_ids: Vec::new(),
            patches: Vec::new(),
            findings: vec![ReviewFindingRecord {
                id: "f1".to_string(),
                status: "open".to_string(),
                severity: "warning".to_string(),
                category: "correctness".to_string(),
                message: "m".to_string(),
                patch_artifact_id: None,
            }],
        },
    });
    let runtime_id = started.runtime_id.unwrap();
    let advanced = apply_runtime_result(ReviewPatchRuntimeResultRequest {
        schema_version: 1,
        runtime_id: runtime_id.clone(),
        succeeded: true,
        error_message: None,
    });
    assert_eq!(advanced.status, "running");
    assert_eq!(advanced.completed_steps, vec!["prepare_patch".to_string()]);
    assert_eq!(advanced.current_step.as_deref(), Some("apply_patch"));

    let state = get_runtime_state(ReviewPatchRuntimeStateRequest {
        schema_version: 1,
        runtime_id,
    });
    assert_eq!(state.completed_steps, vec!["prepare_patch".to_string()]);
    assert_eq!(state.current_step.as_deref(), Some("apply_patch"));
    assert_eq!(state.action.as_deref(), Some("apply_fix"));
}
