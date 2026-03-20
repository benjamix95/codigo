use crate::main_chat::apply_event;
use app_core_protocol::main_chat::{
    MainChatActionRequest, MainChatEvent, MainChatEventKind, MainChatFinishRequest,
    MainChatRuntimeResponse, MainChatStartRequest,
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
