use super::models::{
    ReviewPanelChatFinishRequest, ReviewPanelChatStartRequest, ReviewPanelRuntimeResponse,
};
use super::{cancel_all_streaming_messages, fail_output, finish_output};
use serde_json::{json, Value};

pub fn start_chat_runtime(request: ReviewPanelChatStartRequest) -> ReviewPanelRuntimeResponse {
    let mut state = request.state;
    state.is_chat_processing = true;
    state.chat_started_at = request.started_at;
    if !state.chat_messages.iter().any(|message| {
        message.get("id").and_then(Value::as_str) == Some(request.assistant_message_id.as_str())
    }) {
        state.chat_messages.push(json!({
            "id": request.assistant_message_id,
            "role": "assistant",
            "kind": "reviewRun",
            "content": "",
            "presentation": Value::Null,
            "timestamp": request.message_timestamp.unwrap_or(0.0),
            "isStreaming": true
        }));
    }
    ReviewPanelRuntimeResponse::success(state)
}

pub fn finish_chat_runtime(request: ReviewPanelChatFinishRequest) -> ReviewPanelRuntimeResponse {
    let mut state = request.state;
    state.is_chat_processing = false;
    state.chat_started_at = None;

    let outcome = if request.finish_all_streaming || request.was_cancelled {
        cancel_all_streaming_messages(&mut state);
        ("cancelled", None)
    } else if let Some(error) = request
        .error_message
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
        if let Some(activity_id) = request.assistant_message_id.as_deref() {
            fail_output(
                &mut state,
                activity_id,
                &error,
                request.suggested_verdict_message_id.as_deref(),
            );
        }
        ("failed", Some(error))
    } else {
        if let Some(activity_id) = request.assistant_message_id.as_deref() {
            finish_output(
                &mut state,
                activity_id,
                request.fallback_content.as_deref(),
                request.suggested_verdict_message_id.as_deref(),
            );
        }
        ("completed", None)
    };

    ReviewPanelRuntimeResponse::success_with_outcome(state, outcome.0, outcome.1)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_panel_runtime::models::ReviewPanelRuntimeStateSnapshot;

    fn base_state() -> ReviewPanelRuntimeStateSnapshot {
        ReviewPanelRuntimeStateSnapshot {
            selected_tab: "Chat".to_string(),
            panel_session_id: None,
            selected_finding_id: None,
            selected_historical_finding_id: None,
            immersive_finding_workspace_id: None,
            active_chat_thread_id: None,
            is_running: false,
            run_started_at: None,
            frozen_timer_text: None,
            last_error: None,
            chat_messages: vec![],
            is_chat_processing: false,
            chat_started_at: None,
            response_message_ids: Default::default(),
            finished_review_run_activity_ids: vec![],
        }
    }

    #[test]
    fn start_chat_runtime_appends_assistant_message() {
        let response = start_chat_runtime(ReviewPanelChatStartRequest {
            schema_version: 1,
            state: base_state(),
            assistant_message_id: "assistant-1".to_string(),
            started_at: Some(50.0),
            message_timestamp: Some(55.0),
        });
        let state = response.state.expect("state");
        assert!(state.is_chat_processing);
        assert_eq!(state.chat_messages.len(), 1);
        assert_eq!(state.chat_messages[0]["id"].as_str(), Some("assistant-1"));
    }

    #[test]
    fn finish_chat_runtime_cancels_all_streaming_messages() {
        let mut state = base_state();
        state.is_chat_processing = true;
        state.chat_messages.push(json!({
            "id": "assistant-1",
            "role": "assistant",
            "kind": "reviewRun",
            "content": "",
            "presentation": Value::Null,
            "timestamp": 1.0,
            "isStreaming": true
        }));
        let response = finish_chat_runtime(ReviewPanelChatFinishRequest {
            schema_version: 1,
            state,
            assistant_message_id: None,
            finished_at: Some(60.0),
            error_message: None,
            was_cancelled: true,
            fallback_content: None,
            finish_all_streaming: true,
            suggested_verdict_message_id: None,
        });
        let state = response.state.expect("state");
        assert!(!state.is_chat_processing);
        assert_eq!(
            state.chat_messages[0]["content"].as_str(),
            Some("Cancelled.")
        );
    }
}
