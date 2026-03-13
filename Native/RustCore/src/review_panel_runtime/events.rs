use super::format::{append_section_line, apply_raw_event};
use super::models::{
    ReviewPanelEventReduceRequest, ReviewPanelRuntimeStateSnapshot,
};
use super::state::{
    append_text_delta, clear_message_presentation, finalize_response_message, is_finished,
    mark_finished, replace_response,
};
use serde_json::Value;

pub fn reduce_output_event(request: ReviewPanelEventReduceRequest) -> ReviewPanelRuntimeStateSnapshot {
    let mut state = request.state;
    let activity_id = request.activity_message_id;
    if is_finished(&state, &activity_id) {
        return state;
    }

    match request.event.kind.as_str() {
        "started" => append_section_line(&mut state, &activity_id, "Activity", "Review stream started"),
        "completed" => append_section_line(&mut state, &activity_id, "Activity", "Review stream completed"),
        "textDelta" => {
            if let Some(delta) = request.event.text {
                append_text_delta(
                    &mut state,
                    &activity_id,
                    &delta,
                    request.suggested_response_message_id.as_deref(),
                    request.timestamp,
                );
            }
        }
        "textReplace" => {
            if let Some(replacement) = request.event.text {
                replace_response(
                    &mut state,
                    &activity_id,
                    &replacement,
                    request.suggested_response_message_id.as_deref(),
                    request.timestamp,
                );
            }
        }
        "raw" => apply_raw_event(
            &mut state,
            &activity_id,
            &request.event,
            request.suggested_response_message_id.as_deref(),
            request.timestamp,
        ),
        "error" => {
            if let Some(message) = request.event.text {
                append_section_line(
                    &mut state,
                    &activity_id,
                    "Activity",
                    &format!("Error: {message}"),
                );
            }
        }
        _ => {}
    }
    state
}

pub fn finish_output(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    fallback_content: Option<&str>,
    verdict_message_id: Option<&str>,
) {
    if let Some(index) = state
        .chat_messages
        .iter()
        .position(|message| message.get("id").and_then(Value::as_str) == Some(activity_id))
    {
        let content = state.chat_messages[index]
            .get("content")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string();
        if content.is_empty() {
            if let Some(fallback) = fallback_content {
                if let Some(object) = state.chat_messages[index].as_object_mut() {
                    object.insert("content".to_string(), Value::String(fallback.to_string()));
                    object.insert("presentation".to_string(), Value::Null);
                }
            }
        }
        if let Some(object) = state.chat_messages[index].as_object_mut() {
            object.insert("isStreaming".to_string(), Value::Bool(false));
        }
        clear_message_presentation(&mut state.chat_messages[index]);
    }
    finalize_response_message(state, activity_id, verdict_message_id);
    mark_finished(state, activity_id);
}

pub fn fail_output(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    error: &str,
    verdict_message_id: Option<&str>,
) {
    if let Some(index) = state
        .chat_messages
        .iter()
        .position(|message| message.get("id").and_then(Value::as_str) == Some(activity_id))
    {
        if let Some(object) = state.chat_messages[index].as_object_mut() {
            object.insert("content".to_string(), Value::String(format!("Error: {error}")));
            object.insert("isStreaming".to_string(), Value::Bool(false));
            object.insert("presentation".to_string(), Value::Null);
        }
        clear_message_presentation(&mut state.chat_messages[index]);
    }
    finalize_response_message(state, activity_id, verdict_message_id);
    mark_finished(state, activity_id);
}

pub fn cancel_all_streaming_messages(state: &mut ReviewPanelRuntimeStateSnapshot) {
    let mut updated = Vec::with_capacity(state.chat_messages.len());
    for mut message in state.chat_messages.clone() {
        let is_assistant = message.get("role").and_then(Value::as_str) == Some("assistant");
        let is_streaming = message.get("isStreaming").and_then(Value::as_bool).unwrap_or(false);
        let kind = message.get("kind").and_then(Value::as_str).unwrap_or_default();
        if is_assistant && is_streaming {
            if kind == "reviewRun" {
                if message.get("content").and_then(Value::as_str).unwrap_or_default().trim().is_empty() {
                    if let Some(object) = message.as_object_mut() {
                        object.insert("content".to_string(), Value::String("Cancelled.".to_string()));
                        object.insert("presentation".to_string(), Value::Null);
                    }
                }
                if let Some(object) = message.as_object_mut() {
                    object.insert("isStreaming".to_string(), Value::Bool(false));
                }
                clear_message_presentation(&mut message);
                if let Some(id) = message.get("id").and_then(Value::as_str) {
                    mark_finished(state, id);
                }
                updated.push(message);
                continue;
            }
            if kind == "plain" && message.get("content").and_then(Value::as_str).unwrap_or_default().trim().is_empty() {
                continue;
            }
            if let Some(object) = message.as_object_mut() {
                object.insert("isStreaming".to_string(), Value::Bool(false));
            }
        }
        updated.push(message);
    }
    state.chat_messages = updated;
    state.response_message_ids.clear();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_panel_runtime::models::{
        ReviewPanelRuntimeEventEnvelope, ReviewPanelRuntimeStateSnapshot,
    };
    use std::collections::BTreeMap;

    fn base_state() -> ReviewPanelRuntimeStateSnapshot {
        ReviewPanelRuntimeStateSnapshot {
            selected_tab: "Findings".to_string(),
            is_running: false,
            run_started_at: None,
            frozen_timer_text: None,
            last_error: None,
            chat_messages: vec![serde_json::json!({
                "id": "activity-1",
                "role": "assistant",
                "kind": "reviewRun",
                "content": "",
                "presentation": Value::Null,
                "timestamp": 1.0,
                "isStreaming": true
            })],
            is_chat_processing: false,
            chat_started_at: None,
            response_message_ids: Default::default(),
            finished_review_run_activity_ids: vec![],
        }
    }

    #[test]
    fn reduce_event_appends_delta_into_response_message() {
        let request = ReviewPanelEventReduceRequest {
            schema_version: 1,
            state: base_state(),
            activity_message_id: "activity-1".to_string(),
            suggested_response_message_id: Some("response-1".to_string()),
            suggested_verdict_message_id: None,
            timestamp: Some(2.0),
            event: ReviewPanelRuntimeEventEnvelope {
                kind: "textDelta".to_string(),
                text: Some("hello".to_string()),
                event_type: None,
                payload: BTreeMap::new(),
            },
        };
        let state = reduce_output_event(request);
        assert_eq!(state.chat_messages.len(), 2);
        assert_eq!(state.chat_messages[1]["content"].as_str(), Some("hello"));
    }
}
