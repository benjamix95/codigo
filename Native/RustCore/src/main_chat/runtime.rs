use crate::main_chat::apply_event;
use crate::main_chat::continuation::prepare_auto_continuation;
use crate::main_chat::plan_runtime::handle_plan_action;
use crate::main_chat::stream_runtime::{
    apply_direct_stream_provider_event, handle_direct_stream_timeout, register_direct_stream_event,
    start_direct_stream,
};
use app_core_protocol::main_chat::{
    MainChatActionRequest, MainChatEvent, MainChatEventKind, MainChatFinishRequest,
    MainChatRuntimeResponse, MainChatStartRequest,
};
use app_core_protocol::main_chat_runtime::{
    MainChatRuntimeActionRequest, MainChatRuntimeActionResponse,
};
use std::collections::BTreeMap;

pub fn start_turn(request: MainChatStartRequest) -> MainChatRuntimeResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    let mut payload = BTreeMap::new();
    if let Some(status) = request.status.clone() {
        payload.insert("status".to_string(), status);
    }
    if let Some(provider_id) = request.provider_id.clone() {
        payload.insert("provider_id".to_string(), provider_id);
    }
    let event = MainChatEvent {
        id: format!("{}:start", request.state.turn_id),
        conversation_id: request.state.conversation_id.clone(),
        assistant_message_id: request.state.assistant_message_id.clone(),
        turn_id: request.state.turn_id.clone(),
        sequence: request.state.sequence + 1,
        source: request
            .provider_id
            .clone()
            .or_else(|| request.state.provider_id.clone())
            .unwrap_or_else(|| "main-chat".to_string()),
        kind: MainChatEventKind::TurnStarted,
        payload,
        timestamp: request.timestamp,
    };
    MainChatRuntimeResponse::success(apply_event(request.state, &event))
}

pub fn finish_turn(request: MainChatFinishRequest) -> MainChatRuntimeResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    let mut payload = BTreeMap::new();
    let status = request.status.unwrap_or_else(|| {
        if request.was_cancelled {
            "cancelled".to_string()
        } else {
            "completed".to_string()
        }
    });
    payload.insert("status".to_string(), status.clone());
    if let Some(detail) = request.detail {
        payload.insert("detail".to_string(), detail.clone());
        payload.insert("error".to_string(), detail);
    }
    let event = MainChatEvent {
        id: format!("{}:finish", request.state.turn_id),
        conversation_id: request.state.conversation_id.clone(),
        assistant_message_id: request.state.assistant_message_id.clone(),
        turn_id: request.state.turn_id.clone(),
        sequence: request.state.sequence + 1,
        source: request
            .state
            .provider_id
            .clone()
            .unwrap_or_else(|| "main-chat".to_string()),
        kind: if status == "failed" || request.was_cancelled && payload.contains_key("detail") {
            MainChatEventKind::TurnFailed
        } else {
            MainChatEventKind::TurnCompleted
        },
        payload,
        timestamp: request.timestamp,
    };
    MainChatRuntimeResponse::success(apply_event(request.state, &event))
}

pub fn handle_action(request: MainChatActionRequest) -> MainChatRuntimeResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    match request.action.as_str() {
        "restore_snapshot" => MainChatRuntimeResponse::success(request.state),
        "cancel_turn" => finish_turn(MainChatFinishRequest {
            schema_version: 1,
            state: request.state,
            timestamp: request.timestamp.unwrap_or(0.0),
            status: Some(
                request
                    .status
                    .unwrap_or_else(|| "cancelled".to_string()),
            ),
            detail: request.detail,
            was_cancelled: true,
        }),
        "rewind_turn" => {
            let mut state = request.state;
            state.sequence = 0;
            state.is_streaming = false;
            state.started_at = None;
            state.completed_at = None;
            state.updated_at = request.timestamp;
            state.status = request.status.unwrap_or_else(|| "idle".to_string());
            state.text_by_stream_id.clear();
            state.reasoning_by_group_id.clear();
            state.artifacts.clear();
            MainChatRuntimeResponse::success(state)
        }
        _ => MainChatRuntimeResponse::error("unsupported_action", "main chat action not supported"),
    }
}

pub fn handle_runtime_action(request: MainChatRuntimeActionRequest) -> MainChatRuntimeActionResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeActionResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    if let Some(snapshot) = handle_plan_action(
        request.snapshot.clone(),
        &request.action,
        request.text.clone(),
        request.questions.clone(),
        request.plan_content.clone(),
        request.option_full_texts.clone(),
        request.should_run_inline,
    ) {
        return MainChatRuntimeActionResponse::success(snapshot);
    }

    let snapshot = match request.action.as_str() {
        "direct_stream_start" => start_direct_stream(
            request.snapshot,
            request.timestamp,
            request.provider_id,
        ),
        "direct_stream_event_received" => register_direct_stream_event(
            request.snapshot,
            request.timestamp,
            request.status.as_deref() == Some("text"),
        ),
        "direct_stream_timeout" => handle_direct_stream_timeout(
            request.snapshot,
            request.is_initial_poll.unwrap_or(false),
        ),
        "direct_stream_apply_provider_event" => apply_direct_stream_provider_event(
            request.snapshot,
            request.timestamp,
            request.provider_id,
            request.event_kind.as_deref(),
            request.payload,
        ),
        "direct_stream_prepare_continuation" => prepare_auto_continuation(
            request.snapshot,
            request.detail.as_deref().unwrap_or_default(),
            request.text.as_deref().unwrap_or_default(),
        ),
        "direct_stream_complete" | "direct_stream_fail" | "direct_stream_interrupt" => {
            let snapshot_turn_state = request.snapshot.turn_state.clone();
            let finished = finish_turn(MainChatFinishRequest {
                schema_version: 1,
                state: snapshot_turn_state,
                timestamp: request.timestamp.unwrap_or(0.0),
                status: request.status,
                detail: request.detail,
                was_cancelled: request.action == "direct_stream_interrupt",
            });
            let mut snapshot = request.snapshot;
            if let Some(turn_state) = finished.state {
                snapshot.turn_state = turn_state;
            }
            if let Some(output) = snapshot.output.as_mut() {
                output.should_finalize_stream = true;
            }
            snapshot
        }
        "runtime_restore_snapshot" => request.snapshot,
        _ => return MainChatRuntimeActionResponse::error("unsupported_action", "main chat runtime action not supported"),
    };
    MainChatRuntimeActionResponse::success(snapshot)
}

#[cfg(test)]
mod tests {
    use super::{finish_turn, handle_action, start_turn};
    use app_core_protocol::main_chat::{MainChatActionRequest, MainChatFinishRequest, MainChatStartRequest, MainChatTurnState};

    #[test]
    fn start_turn_marks_state_streaming() {
        let response = start_turn(MainChatStartRequest {
            schema_version: 1,
            state: base_state(),
            timestamp: 42.0,
            provider_id: Some("codex".to_string()),
            status: None,
        });
        let state = response.state.expect("state");
        assert!(state.is_streaming);
        assert_eq!(state.status, "streaming");
        assert_eq!(state.provider_id.as_deref(), Some("codex"));
    }

    #[test]
    fn finish_turn_records_failure_detail() {
        let response = finish_turn(MainChatFinishRequest {
            schema_version: 1,
            state: base_state(),
            timestamp: 42.0,
            status: Some("failed".to_string()),
            detail: Some("boom".to_string()),
            was_cancelled: false,
        });
        let state = response.state.expect("state");
        assert!(!state.is_streaming);
        assert_eq!(state.status, "failed");
        assert!(state.artifacts.iter().any(|artifact| artifact.id == "turn-failed"));
    }

    #[test]
    fn rewind_turn_clears_buffers() {
        let mut state = base_state();
        state.sequence = 9;
        state.text_by_stream_id.insert("main".to_string(), "hello".to_string());
        let response = handle_action(MainChatActionRequest {
            schema_version: 1,
            action: "rewind_turn".to_string(),
            state,
            timestamp: Some(12.0),
            status: None,
            detail: None,
        });
        let state = response.state.expect("state");
        assert_eq!(state.sequence, 0);
        assert!(state.text_by_stream_id.is_empty());
        assert_eq!(state.status, "idle");
    }

    fn base_state() -> MainChatTurnState {
        MainChatTurnState {
            conversation_id: "conv".to_string(),
            assistant_message_id: "msg".to_string(),
            turn_id: "turn".to_string(),
            status: "idle".to_string(),
            ..Default::default()
        }
    }
}
