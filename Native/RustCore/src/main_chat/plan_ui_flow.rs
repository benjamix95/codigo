use crate::main_chat::plan_markdown::parse_clarification_questionnaire;
use crate::main_chat::runtime::handle_runtime_action;
use crate::main_chat::state::{ensure_plan_defaults, reset_output};
use app_core_protocol::main_chat::MainChatTurnState;
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanningStateKind, MainChatRuntimeActionRequest,
    MainChatRuntimeSnapshot,
};
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiIntentResponse, MainChatUiState,
};

pub fn apply_plan_runtime_action(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<MainChatUiState, MainChatUiIntentResponse> {
    if let Some(request_conversation_id) = request
        .conversation_id
        .as_ref()
        .filter(|value| !value.trim().is_empty())
    {
        if state.runtime_snapshot.is_none() {
            state.selected_conversation_id = Some(request_conversation_id.clone());
        } else if state
            .selected_conversation_id
            .as_ref()
            .map_or(true, |value| value.trim().is_empty())
        {
            state.selected_conversation_id = Some(request_conversation_id.clone());
        }
    }

    let Some(action) = request.payload.get("action").cloned() else {
        return Err(MainChatUiIntentResponse::error(
            "missing_action",
            "payload.action is required",
        ));
    };
    if state.runtime_snapshot.is_none()
        && state
            .selected_conversation_id
            .as_ref()
            .map_or(true, |value| value.trim().is_empty())
    {
        return Err(MainChatUiIntentResponse::error(
            "missing_conversation_for_plan",
            "conversationId is required when runtimeSnapshot is absent",
        ));
    }
    let response = handle_runtime_action(MainChatRuntimeActionRequest {
        schema_version: 1,
        action,
        snapshot: runtime_snapshot_for_plan_action(&state),
        timestamp: request.timestamp,
        provider_id: None,
        status: None,
        detail: request.payload.get("detail").cloned(),
        text: request.text.clone(),
        questions: request.payload.get("questions").cloned(),
        plan_content: request.payload.get("plan_content").cloned(),
        option_full_texts: parse_string_list(request.payload.get("option_full_texts")),
        should_run_inline: parse_bool_payload(request.payload.get("should_run_inline")),
        is_initial_poll: None,
        event_kind: None,
        payload: Default::default(),
    });
    let Some(runtime_snapshot) = response.runtime_snapshot else {
        return Err(MainChatUiIntentResponse::error(
            "runtime_action_failed",
            "Runtime action did not return a snapshot",
        ));
    };
    state.runtime_snapshot = Some(runtime_snapshot);
    sync_plan_panel_visibility(&mut state);
    Ok(state)
}

pub fn receive_clarification_questions(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<MainChatUiState, MainChatUiIntentResponse> {
    let questions = request
        .text
        .clone()
        .or_else(|| request.payload.get("questions").cloned())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            MainChatUiIntentResponse::error("missing_questions", "questions are required")
        })?;
    let mut runtime_snapshot = required_runtime_snapshot(&state)?;
    ensure_plan_defaults(&mut runtime_snapshot);
    reset_output(&mut runtime_snapshot);
    let plan = runtime_snapshot.plan.as_mut().expect("plan defaults");
    plan.phase = Some(MainChatPlanPhase::Questioning);
    plan.planning_state_kind = Some(MainChatPlanningStateKind::AwaitingClarification);
    plan.clarification_questions = Some(questions);
    plan.clarification_questionnaire = plan
        .clarification_questions
        .as_ref()
        .and_then(|value| parse_clarification_questionnaire(value));
    plan.question_epoch += 1;
    runtime_snapshot
        .output
        .as_mut()
        .expect("output defaults")
        .should_open_plan_panel = true;
    state.runtime_snapshot = Some(runtime_snapshot);
    state.plan_panel_visible = true;
    Ok(state)
}

pub fn set_plan_panel_visible(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<MainChatUiState, MainChatUiIntentResponse> {
    let is_visible = request
        .payload
        .get("visible")
        .and_then(|value| parse_bool_payload(Some(value)))
        .or_else(|| {
            request
                .text
                .as_ref()
                .and_then(|value| parse_bool_payload(Some(value)))
        })
        .ok_or_else(|| {
            MainChatUiIntentResponse::error("missing_visible", "visible flag is required")
        })?;
    state.plan_panel_visible = is_visible;
    Ok(state)
}

fn required_runtime_snapshot(
    state: &MainChatUiState,
) -> Result<app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot, MainChatUiIntentResponse>
{
    state.runtime_snapshot.clone().ok_or_else(|| {
        MainChatUiIntentResponse::error("missing_runtime_snapshot", "runtimeSnapshot is required")
    })
}

/// Primo invio in modalità Plan: spesso non esiste ancora uno `runtime_snapshot` (nessun direct stream).
/// Seed minimo compatible con decode Swift: `MainChatBridgeState` richiede UUID non vuoti per
/// `conversationId` / `assistantMessageId` (stringhe vuote → fallimento decode JSON della risposta FFI).
const PLAN_RUNTIME_SEED_ASSISTANT_MESSAGE_ID: &str = "00000000-0000-0000-0000-000000000001";
const PLAN_RUNTIME_SEED_TURN_ID: &str = "plan-ui-intent-seed";

fn runtime_snapshot_for_plan_action(state: &MainChatUiState) -> MainChatRuntimeSnapshot {
    if let Some(snapshot) = state.runtime_snapshot.clone() {
        return snapshot;
    }
    let conversation_id = state
        .selected_conversation_id
        .clone()
        .filter(|value| !value.trim().is_empty())
        .expect("conversation id checked before seeding runtime snapshot");
    MainChatRuntimeSnapshot {
        turn_state: MainChatTurnState {
            conversation_id,
            assistant_message_id: PLAN_RUNTIME_SEED_ASSISTANT_MESSAGE_ID.to_string(),
            turn_id: PLAN_RUNTIME_SEED_TURN_ID.to_string(),
            status: "idle".to_string(),
            ..Default::default()
        },
        ..Default::default()
    }
}

fn sync_plan_panel_visibility(state: &mut MainChatUiState) {
    if let Some(output) = state
        .runtime_snapshot
        .as_ref()
        .and_then(|snapshot| snapshot.output.as_ref())
    {
        if output.should_open_plan_panel {
            state.plan_panel_visible = true;
        }
    }
}

fn parse_bool_payload(value: Option<&String>) -> Option<bool> {
    value.and_then(|raw| match raw.trim().to_ascii_lowercase().as_str() {
        "true" | "1" | "yes" => Some(true),
        "false" | "0" | "no" => Some(false),
        _ => None,
    })
}

fn parse_string_list(raw: Option<&String>) -> Vec<String> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    if raw.trim().is_empty() {
        return Vec::new();
    }
    serde_json::from_str::<Vec<String>>(raw).unwrap_or_else(|_| vec![raw.clone()])
}
