use super::models::{
    ReviewPatchActionRequest, ReviewPatchRuntimeResponse, ReviewPatchRuntimeResultRequest,
    ReviewPatchRuntimeStartRequest, ReviewPatchRuntimeStateRequest,
};
use super::planner::handle_patch_action;
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

#[derive(Clone, Debug)]
struct ReviewPatchRuntimeSession {
    action: String,
    session_id: String,
    finding_id: String,
    conversation_id: Option<String>,
    runtime_id: String,
    steps: Vec<String>,
    completed_steps: Vec<String>,
    step_index: usize,
    status: RuntimeStatus,
    error_message: Option<String>,
    last_transition_at: f64,
    terminal_reason: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum RuntimeStatus {
    Running,
    Completed,
    Failed,
}

static RUNTIMES: OnceLock<Mutex<HashMap<String, ReviewPatchRuntimeSession>>> = OnceLock::new();

pub fn start_runtime(request: ReviewPatchRuntimeStartRequest) -> ReviewPatchRuntimeResponse {
    let action = request.action.clone();
    let session_id = request.session_id.clone();
    let finding_id = request.finding_id.clone();
    let conversation_id = request.conversation_id.clone();
    let planning = handle_patch_action(ReviewPatchActionRequest {
        schema_version: request.schema_version,
        operation: "plan_execution".to_string(),
        action,
        session_id,
        finding_id,
        conversation_id,
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
        action: request.action,
        session_id: request.session_id,
        finding_id: request.finding_id,
        conversation_id: request.conversation_id,
        runtime_id: runtime_id.clone(),
        steps: planning.steps,
        completed_steps: Vec::new(),
        step_index: 0,
        status: status.clone(),
        error_message: None,
        last_transition_at: timestamp_now(),
        terminal_reason: if status == RuntimeStatus::Completed {
            Some("completed_without_steps".to_string())
        } else {
            None
        },
    };
    let response = response_for(&session, status, current_step, None);
    store().lock().unwrap().insert(runtime_id.clone(), session);
    response
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
        session.last_transition_at = timestamp_now();
        session.terminal_reason = Some("step_failed".to_string());
        return response_for(
            session,
            RuntimeStatus::Failed,
            None,
            session.error_message.clone(),
        );
    }

    if let Some(completed_step) = session.steps.get(session.step_index).cloned() {
        session.completed_steps.push(completed_step);
    }
    session.step_index += 1;
    session.last_transition_at = timestamp_now();
    if session.step_index >= session.steps.len() {
        session.status = RuntimeStatus::Completed;
        session.terminal_reason = Some("completed".to_string());
        return response_for(session, RuntimeStatus::Completed, None, None);
    }
    let next_step = session.steps.get(session.step_index).cloned();
    response_for(session, RuntimeStatus::Running, next_step, None)
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
    response_for(session, session.status.clone(), current_step, session.error_message.clone())
}

fn response_for(
    session: &ReviewPatchRuntimeSession,
    status: RuntimeStatus,
    current_step: Option<String>,
    error_message: Option<String>,
) -> ReviewPatchRuntimeResponse {
    match status {
        RuntimeStatus::Running => ReviewPatchRuntimeResponse::ok(
            session.runtime_id.clone(),
            session.action.clone(),
            session.session_id.clone(),
            session.finding_id.clone(),
            session.conversation_id.clone(),
            "running",
            current_step,
            session.steps.clone(),
            session.completed_steps.clone(),
            Some(session.last_transition_at),
            session.terminal_reason.clone(),
        ),
        RuntimeStatus::Completed => ReviewPatchRuntimeResponse::ok(
            session.runtime_id.clone(),
            session.action.clone(),
            session.session_id.clone(),
            session.finding_id.clone(),
            session.conversation_id.clone(),
            "completed",
            None,
            session.steps.clone(),
            session.completed_steps.clone(),
            Some(session.last_transition_at),
            session.terminal_reason.clone(),
        ),
        RuntimeStatus::Failed => ReviewPatchRuntimeResponse {
            schema_version: 1,
            is_error: false,
            error_code: None,
            error_message,
            action: Some(session.action.clone()),
            session_id: Some(session.session_id.clone()),
            finding_id: Some(session.finding_id.clone()),
            conversation_id: session.conversation_id.clone(),
            runtime_id: Some(session.runtime_id.clone()),
            status: "failed".to_string(),
            current_step: None,
            steps: session.steps.clone(),
            completed_steps: session.completed_steps.clone(),
            last_transition_at: Some(session.last_transition_at),
            terminal_reason: session.terminal_reason.clone(),
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

fn timestamp_now() -> f64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
