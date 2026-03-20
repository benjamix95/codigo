use crate::main_chat::runtime::handle_runtime_action;
use crate::main_chat::ui_state_sync::{
    apply_terminal_text_override, mark_store_stream_finished, sync_store_from_runtime,
};
use crate::main_chat::ui_projection::project_ui;
use app_core_protocol::main_chat_runtime::MainChatRuntimeActionRequest;
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiIntentResponse, MainChatUiProjectRequest,
};

pub fn handle_ui_intent(request: MainChatUiIntentRequest) -> MainChatUiIntentResponse {
    if request.schema_version != 1 {
        return MainChatUiIntentResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let mut state = request.state;
    match request.intent.as_str() {
        "select_conversation" => {
            state.selected_conversation_id = request.conversation_id;
        }
        "set_draft_text" => {
            state.draft_text = request.text.unwrap_or_default();
        }
        "stream_replace_text" | "stream_append_reasoning" => {
            sync_store_from_runtime(&mut state);
        }
        "stream_apply_raw_event" => {
            let payload = request
                .payload
                .iter()
                .filter(|(key, _)| *key != "event_kind" && *key != "provider_id")
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect();
            let response = handle_runtime_action(MainChatRuntimeActionRequest {
                schema_version: 1,
                action: "direct_stream_apply_provider_event".to_string(),
                snapshot: match state.runtime_snapshot.clone() {
                    Some(snapshot) => snapshot,
                    None => {
                        return MainChatUiIntentResponse::error(
                            "missing_runtime_snapshot",
                            "runtimeSnapshot is required",
                        )
                    }
                },
                timestamp: request.timestamp,
                provider_id: request.payload.get("provider_id").cloned(),
                status: None,
                detail: None,
                text: None,
                questions: None,
                plan_content: None,
                option_full_texts: Vec::new(),
                should_run_inline: None,
                is_initial_poll: None,
                event_kind: request.payload.get("event_kind").cloned(),
                payload,
            });
            let Some(runtime_snapshot) = response.runtime_snapshot else {
                return MainChatUiIntentResponse::error(
                    "runtime_action_failed",
                    "Runtime action did not return a snapshot",
                );
            };
            state.runtime_snapshot = Some(runtime_snapshot);
            sync_store_from_runtime(&mut state);
        }
        "stream_finish_success" | "stream_finish_failure" | "stream_interrupt" => {
            sync_store_from_runtime(&mut state);
            if let Some(text) = request.text.as_deref() {
                apply_terminal_text_override(&mut state, text);
            }
            mark_store_stream_finished(&mut state);
        }
        "stream_clear_ephemeral_state" => {}
        "toggle_artifact_collapsed" => {
            let Some(artifact_id) = request.artifact_id else {
                return MainChatUiIntentResponse::error("missing_artifact_id", "artifactId is required");
            };
            let turn_id = request
                .turn_id
                .or_else(|| state.runtime_snapshot.as_ref().map(|snapshot| snapshot.turn_state.turn_id.clone()));
            let Some(turn_id) = turn_id else {
                return MainChatUiIntentResponse::error("missing_turn_id", "turnId is required");
            };
            let entry = state.collapsed_artifact_ids_by_turn.entry(turn_id).or_default();
            if let Some(index) = entry.iter().position(|candidate| candidate == &artifact_id) {
                entry.remove(index);
            } else {
                entry.push(artifact_id);
            }
        }
        "cancel_turn" => {
            state = match apply_runtime_action(
                state,
                "direct_stream_interrupt",
                request.timestamp,
                None,
                request.text,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "rewind_turn" => {
            state = match apply_runtime_action(
                state,
                "rewind_turn",
                request.timestamp,
                Some("idle".to_string()),
                None,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "submit_clarification_answers" => {
            state = match apply_runtime_action(
                state,
                "plan_apply_clarification_answers",
                request.timestamp,
                None,
                request.text,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "choose_plan_option" => {
            let Some(conversation_id) = request
                .conversation_id
                .clone()
                .or_else(|| state.selected_conversation_id.clone()) else {
                return MainChatUiIntentResponse::error("missing_conversation_id", "conversationId is required");
            };
            let Some(chosen_path) = request.text.clone() else {
                return MainChatUiIntentResponse::error("missing_text", "text is required");
            };
            if let Some(board) = state.store_snapshot.plan_boards.get_mut(&conversation_id) {
                board.chosen_path = Some(chosen_path);
            }
            state = match apply_runtime_action(
                state,
                "plan_ready_to_build",
                request.timestamp,
                None,
                request.text,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "begin_plan_build" => {
            state = match apply_runtime_action(
                state,
                "plan_begin_build",
                request.timestamp,
                None,
                None,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "restore_snapshot" => {}
        _ => {
            return MainChatUiIntentResponse::error("unsupported_intent", "Unsupported main chat UI intent");
        }
    }

    let snapshot = project_ui(MainChatUiProjectRequest {
        schema_version: 1,
        state: state.clone(),
    });
    match snapshot.snapshot {
        Some(snapshot) => MainChatUiIntentResponse::success(state, snapshot),
        None => MainChatUiIntentResponse::error("projection_failed", "Failed to project UI snapshot"),
    }
}

fn apply_runtime_action(
    mut state: app_core_protocol::main_chat_ui::MainChatUiState,
    action: &str,
    timestamp: Option<f64>,
    status: Option<String>,
    text: Option<String>,
) -> Result<app_core_protocol::main_chat_ui::MainChatUiState, MainChatUiIntentResponse> {
    let Some(snapshot) = state.runtime_snapshot.clone() else {
        return Err(MainChatUiIntentResponse::error("missing_runtime_snapshot", "runtimeSnapshot is required"));
    };
    let response = handle_runtime_action(MainChatRuntimeActionRequest {
        schema_version: 1,
        action: action.to_string(),
        snapshot,
        timestamp,
        provider_id: None,
        status,
        detail: text.clone(),
        text,
        questions: None,
        plan_content: None,
        option_full_texts: Vec::new(),
        should_run_inline: None,
        is_initial_poll: None,
        event_kind: None,
        payload: Default::default(),
    });
    let Some(runtime_snapshot) = response.runtime_snapshot else {
        return Err(MainChatUiIntentResponse::error("runtime_action_failed", "Runtime action did not return a snapshot"));
    };
    state.runtime_snapshot = Some(runtime_snapshot);
    Ok(state)
}
