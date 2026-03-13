use super::models::ReviewPanelRuntimeStateSnapshot;
use crate::review_value::ensure_object;
use serde_json::{json, Value};
use std::collections::HashSet;

pub fn append_text_delta(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    delta: &str,
    response_message_id: Option<&str>,
    timestamp: Option<f64>,
) {
    let Some(index) = response_index(state, activity_id, response_message_id, timestamp) else {
        return;
    };
    let current = message_content(&state.chat_messages[index]).to_string();
    set_message_content(&mut state.chat_messages[index], current + delta);
}

pub fn replace_response(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    replacement: &str,
    response_message_id: Option<&str>,
    timestamp: Option<f64>,
) {
    let Some(index) = response_index(state, activity_id, response_message_id, timestamp) else {
        return;
    };
    set_message_content(&mut state.chat_messages[index], replacement.to_string());
}

pub fn finalize_response_message(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    verdict_message_id: Option<&str>,
) {
    let Some(response_id) = state.response_message_ids.get(activity_id).cloned() else {
        return;
    };
    let Some(response_index) = message_index(&state.chat_messages, &response_id) else {
        state.response_message_ids.remove(activity_id);
        return;
    };

    let content = message_content(&state.chat_messages[response_index]).trim().to_string();
    if content.is_empty() {
        state.chat_messages.remove(response_index);
        state.response_message_ids.remove(activity_id);
        return;
    }

    set_message_streaming(&mut state.chat_messages[response_index], false);
    let separator = "\n---\n";
    if let Some((response_part, verdict_part)) = split_verdict(&content, separator) {
        if response_part.is_empty() {
            state.chat_messages.remove(response_index);
        } else if let Some(index) = message_index(&state.chat_messages, &response_id) {
            set_message_content(&mut state.chat_messages[index], response_part.clone());
            set_message_streaming(&mut state.chat_messages[index], false);
        }
        if !verdict_part.is_empty() {
            if let Some(verdict_id) = verdict_message_id {
                let verdict_message =
                    make_message(verdict_id, "assistant", "reviewRun", &verdict_part, 0.0, false);
                let insert_at = message_index(&state.chat_messages, &response_id)
                    .map(|index| index + 1)
                    .unwrap_or(response_index);
                state.chat_messages.insert(insert_at, verdict_message);
            }
        }
    }
    state.response_message_ids.remove(activity_id);
}

pub fn mark_finished(state: &mut ReviewPanelRuntimeStateSnapshot, activity_id: &str) {
    let mut ids = state
        .finished_review_run_activity_ids
        .iter()
        .cloned()
        .collect::<HashSet<_>>();
    if ids.insert(activity_id.to_string()) {
        state.finished_review_run_activity_ids = ids.into_iter().collect();
        state.finished_review_run_activity_ids.sort();
    }
}

pub fn is_finished(state: &ReviewPanelRuntimeStateSnapshot, activity_id: &str) -> bool {
    state
        .finished_review_run_activity_ids
        .iter()
        .any(|id| id == activity_id)
}

fn response_index(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    response_message_id: Option<&str>,
    timestamp: Option<f64>,
) -> Option<usize> {
    if let Some(existing_id) = state.response_message_ids.get(activity_id) {
        if let Some(index) = message_index(&state.chat_messages, existing_id) {
            return Some(index);
        }
    }

    let response_id = response_message_id?;
    let message = make_message(
        response_id,
        "assistant",
        "plain",
        "",
        timestamp.unwrap_or(0.0),
        true,
    );
    state
        .response_message_ids
        .insert(activity_id.to_string(), response_id.to_string());
    if let Some(activity_index) = message_index(&state.chat_messages, activity_id) {
        state.chat_messages.insert(activity_index + 1, message);
        Some(activity_index + 1)
    } else {
        state.chat_messages.push(message);
        Some(state.chat_messages.len() - 1)
    }
}

fn split_verdict(content: &str, separator: &str) -> Option<(String, String)> {
    let parts = content.split_once(separator)?;
    Some((parts.0.trim().to_string(), parts.1.trim().to_string()))
}

fn message_index(messages: &[Value], id: &str) -> Option<usize> {
    messages
        .iter()
        .position(|message| message_id(message).as_deref() == Some(id))
}

fn message_id(message: &Value) -> Option<String> {
    message
        .get("id")
        .and_then(Value::as_str)
        .map(ToString::to_string)
}

fn message_content(message: &Value) -> &str {
    message
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or_default()
}

fn set_message_content(message: &mut Value, content: String) {
    let object = ensure_object(message);
    object.insert("content".to_string(), Value::String(content));
    object.insert("presentation".to_string(), Value::Null);
}

fn set_message_streaming(message: &mut Value, is_streaming: bool) {
    ensure_object(message).insert("isStreaming".to_string(), Value::Bool(is_streaming));
}

pub fn clear_message_presentation(message: &mut Value) {
    ensure_object(message).insert("presentation".to_string(), Value::Null);
}

fn make_message(
    id: &str,
    role: &str,
    kind: &str,
    content: &str,
    timestamp: f64,
    is_streaming: bool,
) -> Value {
    json!({
        "id": id,
        "role": role,
        "kind": kind,
        "content": content,
        "presentation": Value::Null,
        "timestamp": timestamp,
        "isStreaming": is_streaming
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_panel_runtime::models::ReviewPanelRuntimeStateSnapshot;

    fn base_state() -> ReviewPanelRuntimeStateSnapshot {
        ReviewPanelRuntimeStateSnapshot {
            selected_tab: "Findings".to_string(),
            is_running: false,
            run_started_at: None,
            frozen_timer_text: None,
            last_error: None,
            chat_messages: vec![json!({
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
    fn finalize_response_message_splits_verdict() {
        let mut state = base_state();
        state
            .response_message_ids
            .insert("activity-1".to_string(), "response-1".to_string());
        state.chat_messages.push(json!({
            "id": "response-1",
            "role": "assistant",
            "kind": "plain",
            "content": "Body\n---\nVerdict",
            "presentation": Value::Null,
            "timestamp": 2.0,
            "isStreaming": true
        }));
        finalize_response_message(&mut state, "activity-1", Some("verdict-1"));
        assert!(state.response_message_ids.is_empty());
        assert_eq!(state.chat_messages[1]["content"].as_str(), Some("Body"));
        assert_eq!(state.chat_messages[2]["id"].as_str(), Some("verdict-1"));
    }
}
