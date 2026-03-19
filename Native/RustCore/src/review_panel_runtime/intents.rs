use super::models::{ReviewPanelIntentRequest, ReviewPanelRuntimeResponse};

pub fn apply_intent(request: ReviewPanelIntentRequest) -> ReviewPanelRuntimeResponse {
    let mut state = request.state;
    match request.intent.as_str() {
        "select_tab" => {
            if let Some(tab) = normalized_value(request.value) {
                state.selected_tab = tab;
            }
        }
        "set_selected_session" => {
            state.panel_session_id = normalized_value(request.value);
            state.selected_finding_id = None;
            state.selected_historical_finding_id = None;
        }
        "set_active_chat_thread" => {
            state.active_chat_thread_id = normalized_value(request.value);
        }
        "clear_active_chat_thread" => {
            state.active_chat_thread_id = None;
        }
        "bind_panel_session" => {
            state.panel_session_id = normalized_value(request.value);
        }
        "focus_finding" => {
            state.selected_finding_id = normalized_value(request.value);
            state.selected_historical_finding_id = None;
        }
        "focus_historical_finding" => {
            state.selected_finding_id = None;
            state.selected_historical_finding_id = normalized_value(request.value);
        }
        "clear_selected_finding" => {
            state.selected_finding_id = None;
        }
        "clear_selected_historical_finding" => {
            state.selected_historical_finding_id = None;
        }
        intent => {
            return ReviewPanelRuntimeResponse::error(
                "unsupported_intent",
                &format!("Unsupported review panel intent: {intent}"),
            );
        }
    }
    ReviewPanelRuntimeResponse::success(state)
}

fn normalized_value(value: Option<String>) -> Option<String> {
    value.map(|item| item.trim().to_string()).filter(|item| !item.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_panel_runtime::models::ReviewPanelRuntimeStateSnapshot;

    fn base_state() -> ReviewPanelRuntimeStateSnapshot {
        ReviewPanelRuntimeStateSnapshot {
            selected_tab: "Findings".to_string(),
            panel_session_id: Some("session-a".to_string()),
            selected_finding_id: Some("finding-a".to_string()),
            selected_historical_finding_id: Some("hist-a".to_string()),
            active_chat_thread_id: Some("thread-a".to_string()),
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
    fn set_selected_session_clears_detail_selection() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "set_selected_session".to_string(),
            value: Some("session-b".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.panel_session_id.as_deref(), Some("session-b"));
        assert_eq!(state.selected_finding_id, None);
        assert_eq!(state.selected_historical_finding_id, None);
    }

    #[test]
    fn select_tab_updates_selected_tab_only() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "select_tab".to_string(),
            value: Some("Chat".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.selected_tab, "Chat");
        assert_eq!(state.panel_session_id.as_deref(), Some("session-a"));
        assert_eq!(state.selected_finding_id.as_deref(), Some("finding-a"));
        assert_eq!(state.selected_historical_finding_id.as_deref(), Some("hist-a"));
    }

    #[test]
    fn bind_panel_session_preserves_other_selection_state() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "bind_panel_session".to_string(),
            value: Some("session-b".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.panel_session_id.as_deref(), Some("session-b"));
        assert_eq!(state.selected_finding_id.as_deref(), Some("finding-a"));
        assert_eq!(state.selected_historical_finding_id.as_deref(), Some("hist-a"));
        assert_eq!(state.active_chat_thread_id.as_deref(), Some("thread-a"));
    }

    #[test]
    fn set_active_chat_thread_updates_only_thread_selection() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "set_active_chat_thread".to_string(),
            value: Some("thread-b".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.active_chat_thread_id.as_deref(), Some("thread-b"));
        assert_eq!(state.panel_session_id.as_deref(), Some("session-a"));
        assert_eq!(state.selected_finding_id.as_deref(), Some("finding-a"));
        assert_eq!(state.selected_historical_finding_id.as_deref(), Some("hist-a"));
        assert_eq!(state.selected_tab, "Findings");
    }

    #[test]
    fn focus_finding_clears_historical_selection() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "focus_finding".to_string(),
            value: Some("finding-b".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.selected_finding_id.as_deref(), Some("finding-b"));
        assert_eq!(state.selected_historical_finding_id, None);
    }

    #[test]
    fn focus_historical_finding_clears_live_finding_selection() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: base_state(),
            intent: "focus_historical_finding".to_string(),
            value: Some("hist-b".to_string()),
        });
        let state = response.state.expect("state");
        assert_eq!(state.selected_finding_id, None);
        assert_eq!(state.selected_historical_finding_id.as_deref(), Some("hist-b"));
    }

    #[test]
    fn clear_intents_are_idempotent() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: ReviewPanelRuntimeStateSnapshot {
                selected_finding_id: None,
                selected_historical_finding_id: None,
                active_chat_thread_id: None,
                ..base_state()
            },
            intent: "clear_selected_historical_finding".to_string(),
            value: None,
        });
        let state = response.state.expect("state");
        assert_eq!(state.selected_finding_id, None);
        assert_eq!(state.selected_historical_finding_id, None);
        assert_eq!(state.active_chat_thread_id, None);
    }

    #[test]
    fn clear_active_chat_thread_is_idempotent() {
        let response = apply_intent(ReviewPanelIntentRequest {
            schema_version: 1,
            state: ReviewPanelRuntimeStateSnapshot {
                active_chat_thread_id: None,
                ..base_state()
            },
            intent: "clear_active_chat_thread".to_string(),
            value: None,
        });
        let state = response.state.expect("state");
        assert_eq!(state.active_chat_thread_id, None);
        assert_eq!(state.panel_session_id.as_deref(), Some("session-a"));
        assert_eq!(state.selected_tab, "Findings");
    }
}
