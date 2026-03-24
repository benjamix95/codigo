use crate::main_chat::apply_event;
use crate::main_chat::auto_todo::{
    begin_runtime as begin_auto_todo_runtime, discard_runtime as discard_auto_todo_runtime,
    finalize_runtime as finalize_auto_todo_runtime, record_operation as record_auto_todo_operation,
};
use crate::main_chat::plan_ui_flow::{
    apply_plan_runtime_action, receive_clarification_questions, set_plan_panel_visible,
};
use crate::main_chat::runtime::handle_runtime_action;
use crate::main_chat::ui_projection::project_ui;
use crate::main_chat::ui_state_sync::{
    apply_terminal_text_override, mark_store_stream_finished, sync_store_from_runtime,
};
use app_core_protocol::main_chat_runtime::MainChatRuntimeActionRequest;
use app_core_protocol::main_chat_store::{
    MainChatStorePlanBoardSnapshot, MainChatStorePlanOptionSnapshot, MainChatStorePlanStepSnapshot,
};
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiIntentResponse, MainChatUiProjectRequest,
};

pub fn handle_ui_intent(request: MainChatUiIntentRequest) -> MainChatUiIntentResponse {
    if request.schema_version != 1 {
        return MainChatUiIntentResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let mut state = request.state.clone();
    let mut todo_patches = Vec::new();
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
        "pipeline_apply_event" => {
            state = match apply_pipeline_event(state, &request) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "pipeline_apply_events" => {
            state = match apply_pipeline_events(state, &request) {
                Ok(state) => state,
                Err(error) => return error,
            };
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
                return MainChatUiIntentResponse::error(
                    "missing_artifact_id",
                    "artifactId is required",
                );
            };
            let turn_id = request.turn_id.or_else(|| {
                state
                    .runtime_snapshot
                    .as_ref()
                    .map(|snapshot| snapshot.turn_state.turn_id.clone())
            });
            let Some(turn_id) = turn_id else {
                return MainChatUiIntentResponse::error("missing_turn_id", "turnId is required");
            };
            let entry = state
                .collapsed_artifact_ids_by_turn
                .entry(turn_id)
                .or_default();
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
                None,
                None,
                Vec::new(),
                None,
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
                None,
                None,
                Vec::new(),
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
                None,
                None,
                Vec::new(),
                None,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "choose_plan_option" => {
            let Some(conversation_id) = request
                .conversation_id
                .clone()
                .or_else(|| state.selected_conversation_id.clone())
            else {
                return MainChatUiIntentResponse::error(
                    "missing_conversation_id",
                    "conversationId is required",
                );
            };
            let Some(chosen_path) = request.text.clone() else {
                return MainChatUiIntentResponse::error("missing_text", "text is required");
            };
            state = match apply_runtime_action(
                state,
                "plan_choose_option",
                request.timestamp,
                None,
                Some(chosen_path.clone()),
                None,
                None,
                Vec::new(),
                None,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
            let choice_is_valid = state
                .runtime_snapshot
                .as_ref()
                .and_then(|runtime| runtime.plan.as_ref())
                .and_then(|plan| plan.chosen_path.as_ref())
                .map(|value| value.trim() == chosen_path.trim())
                .unwrap_or(false);
            if !choice_is_valid {
                return MainChatUiIntentResponse::error(
                    "invalid_plan_choice",
                    "Selected plan option is missing a valid todo checklist",
                );
            }
            sync_plan_board_from_runtime(&mut state, &conversation_id, request.timestamp);
            state = match apply_runtime_action(
                state,
                "plan_ready_to_build",
                request.timestamp,
                None,
                Some(chosen_path),
                None,
                None,
                Vec::new(),
                None,
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
                None,
                None,
                Vec::new(),
                None,
            ) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "apply_plan_runtime_action" => {
            state = match apply_plan_runtime_action(state, &request) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "plan_receive_clarification_questions" => {
            state = match receive_clarification_questions(state, &request) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "set_plan_panel_visible" => {
            state = match set_plan_panel_visible(state, &request) {
                Ok(state) => state,
                Err(error) => return error,
            };
        }
        "auto_todo_begin_runtime" => {
            (state, todo_patches) = match begin_auto_todo_runtime(state, &request) {
                Ok(result) => result,
                Err(error) => return error,
            };
        }
        "auto_todo_record_operation" => {
            (state, todo_patches) = match record_auto_todo_operation(state, &request) {
                Ok(result) => result,
                Err(error) => return error,
            };
        }
        "auto_todo_finalize_runtime" => {
            (state, todo_patches) = match finalize_auto_todo_runtime(state, &request) {
                Ok(result) => result,
                Err(error) => return error,
            };
        }
        "auto_todo_discard_runtime" => {
            (state, todo_patches) = match discard_auto_todo_runtime(state, &request) {
                Ok(result) => result,
                Err(error) => return error,
            };
        }
        "restore_snapshot" => {}
        _ => {
            return MainChatUiIntentResponse::error(
                "unsupported_intent",
                "Unsupported main chat UI intent",
            );
        }
    }

    let snapshot = project_ui(MainChatUiProjectRequest {
        schema_version: 1,
        state: state.clone(),
    });
    match snapshot.snapshot {
        Some(snapshot) => {
            MainChatUiIntentResponse::success_with_patches(state, snapshot, todo_patches)
        }
        None => {
            MainChatUiIntentResponse::error("projection_failed", "Failed to project UI snapshot")
        }
    }
}

fn apply_runtime_action(
    mut state: app_core_protocol::main_chat_ui::MainChatUiState,
    action: &str,
    timestamp: Option<f64>,
    status: Option<String>,
    text: Option<String>,
    questions: Option<String>,
    plan_content: Option<String>,
    option_full_texts: Vec<String>,
    should_run_inline: Option<bool>,
) -> Result<app_core_protocol::main_chat_ui::MainChatUiState, MainChatUiIntentResponse> {
    let Some(snapshot) = state.runtime_snapshot.clone() else {
        return Err(MainChatUiIntentResponse::error(
            "missing_runtime_snapshot",
            "runtimeSnapshot is required",
        ));
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
        questions,
        plan_content,
        option_full_texts,
        should_run_inline,
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
    Ok(state)
}

fn apply_pipeline_event(
    mut state: app_core_protocol::main_chat_ui::MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<app_core_protocol::main_chat_ui::MainChatUiState, MainChatUiIntentResponse> {
    let Some(mut snapshot) = state.runtime_snapshot.clone() else {
        return Err(MainChatUiIntentResponse::error(
            "missing_runtime_snapshot",
            "runtimeSnapshot is required",
        ));
    };
    let Some(event) = request.pipeline_event.clone() else {
        return Err(MainChatUiIntentResponse::error(
            "missing_pipeline_event",
            "pipelineEvent is required",
        ));
    };
    snapshot.turn_state = apply_event(snapshot.turn_state, &event);
    state.runtime_snapshot = Some(snapshot);
    sync_store_from_runtime(&mut state);
    Ok(state)
}

fn apply_pipeline_events(
    mut state: app_core_protocol::main_chat_ui::MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<app_core_protocol::main_chat_ui::MainChatUiState, MainChatUiIntentResponse> {
    let Some(mut snapshot) = state.runtime_snapshot.clone() else {
        return Err(MainChatUiIntentResponse::error(
            "missing_runtime_snapshot",
            "runtimeSnapshot is required",
        ));
    };
    if request.pipeline_events.is_empty() {
        return Err(MainChatUiIntentResponse::error(
            "missing_pipeline_events",
            "pipelineEvents is required",
        ));
    }
    for event in &request.pipeline_events {
        snapshot.turn_state = apply_event(snapshot.turn_state, event);
    }
    state.runtime_snapshot = Some(snapshot);
    sync_store_from_runtime(&mut state);
    Ok(state)
}

fn sync_plan_board_from_runtime(
    state: &mut app_core_protocol::main_chat_ui::MainChatUiState,
    conversation_id: &str,
    timestamp: Option<f64>,
) {
    let Some(plan) = state
        .runtime_snapshot
        .as_ref()
        .and_then(|runtime| runtime.plan.as_ref())
    else {
        return;
    };

    let existing = state
        .store_snapshot
        .plan_boards
        .get(conversation_id)
        .cloned();
    let options = plan
        .option_full_texts
        .iter()
        .enumerate()
        .map(|(index, full_text)| MainChatStorePlanOptionSnapshot {
            id: index as i32 + 1,
            title: plan
                .option_titles
                .get(index)
                .cloned()
                .unwrap_or_else(|| format!("Option {}", index + 1)),
            full_text: full_text.clone(),
        })
        .collect::<Vec<_>>();
    let steps = plan
        .canonical_todos
        .iter()
        .enumerate()
        .map(|(index, title)| MainChatStorePlanStepSnapshot {
            id: format!("{}", index + 1),
            title: title.clone(),
            description: title.clone(),
            target_file: None,
            status: "pending".to_string(),
            linked_files: Vec::new(),
            depends_on: if index == 0 {
                Vec::new()
            } else {
                vec![format!("{}", index)]
            },
            notes: String::new(),
            updated_at: timestamp,
        })
        .collect::<Vec<_>>();

    let board = MainChatStorePlanBoardSnapshot {
        goal: plan
            .summary_title
            .clone()
            .or_else(|| existing.as_ref().map(|board| board.goal.clone()))
            .unwrap_or_else(|| plan.user_request.clone()),
        options: if !options.is_empty() {
            options
        } else {
            existing
                .as_ref()
                .map(|board| board.options.clone())
                .unwrap_or_default()
        },
        chosen_path: plan.chosen_path.clone().or_else(|| {
            existing
                .as_ref()
                .and_then(|board| board.chosen_path.clone())
        }),
        steps: if !steps.is_empty() {
            steps
        } else {
            existing
                .as_ref()
                .map(|board| board.steps.clone())
                .unwrap_or_default()
        },
        updated_at: timestamp.or_else(|| existing.as_ref().and_then(|board| board.updated_at)),
        walkthrough_markdown: existing
            .as_ref()
            .and_then(|board| board.walkthrough_markdown.clone()),
        walkthrough_summary: existing
            .as_ref()
            .and_then(|board| board.walkthrough_summary.clone()),
        walkthrough_outcome: existing
            .as_ref()
            .and_then(|board| board.walkthrough_outcome.clone()),
    };

    state
        .store_snapshot
        .plan_boards
        .insert(conversation_id.to_string(), board);
}
