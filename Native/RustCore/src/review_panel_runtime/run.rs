use super::models::{
    ReviewPanelRunFinishRequest, ReviewPanelRunStartRequest, ReviewPanelRuntimeResponse,
};

pub fn start_run_runtime(request: ReviewPanelRunStartRequest) -> ReviewPanelRuntimeResponse {
    let mut state = request.state;
    state.selected_tab = request.selected_tab_on_start;
    state.is_running = true;
    state.run_started_at = request.started_at;
    state.frozen_timer_text = None;
    state.last_error = None;
    ReviewPanelRuntimeResponse::success(state)
}

pub fn finish_run_runtime(request: ReviewPanelRunFinishRequest) -> ReviewPanelRuntimeResponse {
    let mut state = request.state;
    let outcome = if request.was_cancelled {
        state.last_error = None;
        ("cancelled", Some("Review cancelled".to_string()))
    } else if let Some(error) = request
        .error_message
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
        state.last_error = Some(error.clone());
        ("failed", Some(error))
    } else if request.snapshot_phase.as_deref() == Some("completed") {
        state.last_error = None;
        ("completed", None)
    } else {
        let message = request
            .snapshot_last_error
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| {
                format!(
                    "Review did not complete (phase: {})",
                    request.snapshot_phase.as_deref().unwrap_or("unknown")
                )
            });
        state.last_error = Some(message.clone());
        ("failed", Some(message))
    };

    state.is_running = false;
    // Solo run davvero completato: altrimenti il footer Swift mostrava "Completed in 0:00" su failed/cancel
    // o quando lo snapshot non era ancora terminale.
    if outcome.0 == "completed" {
        state.frozen_timer_text = freeze_timer(state.run_started_at, request.finished_at);
    } else {
        state.frozen_timer_text = None;
    }
    if state.selected_tab != "Chat" {
        state.selected_tab = request.selected_tab_on_finish;
    }
    ReviewPanelRuntimeResponse::success_with_outcome(state, outcome.0, outcome.1)
}

fn freeze_timer(start: Option<f64>, finish: Option<f64>) -> Option<String> {
    let elapsed = (finish? - start?).max(0.0).floor() as i64;
    Some(format!("{}:{:02}", elapsed / 60, elapsed % 60))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_panel_runtime::models::ReviewPanelRuntimeStateSnapshot;

    fn base_request() -> ReviewPanelRunStartRequest {
        ReviewPanelRunStartRequest {
            schema_version: 1,
            state: ReviewPanelRuntimeStateSnapshot {
                selected_tab: "Findings".to_string(),
                panel_session_id: None,
                selected_finding_id: None,
                selected_historical_finding_id: None,
                immersive_finding_workspace_id: None,
                active_chat_thread_id: None,
                is_running: false,
                run_started_at: None,
                frozen_timer_text: Some("0:01".to_string()),
                last_error: Some("old".to_string()),
                chat_messages: vec![],
                is_chat_processing: false,
                chat_started_at: None,
                response_message_ids: Default::default(),
                finished_review_run_activity_ids: vec![],
            },
            selected_tab_on_start: "Chat".to_string(),
            started_at: Some(100.0),
        }
    }

    #[test]
    fn start_run_runtime_sets_running_state() {
        let response = start_run_runtime(base_request());
        let state = response.state.expect("state");
        assert!(state.is_running);
        assert_eq!(state.selected_tab, "Chat");
        assert_eq!(state.run_started_at, Some(100.0));
        assert_eq!(state.last_error, None);
    }

    #[test]
    fn finish_run_runtime_marks_failure_when_snapshot_not_terminal() {
        let start = start_run_runtime(base_request()).state.expect("state");
        let response = finish_run_runtime(ReviewPanelRunFinishRequest {
            schema_version: 1,
            state: start,
            selected_tab_on_finish: "Findings".to_string(),
            finished_at: Some(165.0),
            snapshot_phase: Some("verifying".to_string()),
            snapshot_last_error: None,
            error_message: None,
            was_cancelled: false,
        });
        let state = response.state.expect("state");
        assert!(!state.is_running);
        assert_eq!(
            state.last_error.as_deref(),
            Some("Review did not complete (phase: verifying)")
        );
        assert_eq!(state.frozen_timer_text, None);
        assert_eq!(response.outcome.expect("outcome").status, "failed");
    }
}
