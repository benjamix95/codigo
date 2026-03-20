use crate::main_chat::state::{ensure_direct_stream_defaults, reset_output};
use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;

pub fn start_direct_stream(
    mut snapshot: MainChatRuntimeSnapshot,
    timestamp: Option<f64>,
    provider_id: Option<String>,
) -> MainChatRuntimeSnapshot {
    ensure_direct_stream_defaults(&mut snapshot);
    reset_output(&mut snapshot);
    if let Some(direct) = snapshot.direct_stream.as_mut() {
        direct.initial_retry_count = 0;
        direct.stall_retry_count = 0;
        direct.has_received_any_event = false;
        direct.emitted_first_text = false;
        direct.stream_started_at = timestamp;
        direct.last_event_at = timestamp;
    }
    if let Some(provider_id) = provider_id {
        snapshot.turn_state.provider_id = Some(provider_id);
    }
    snapshot
}

pub fn register_direct_stream_event(
    mut snapshot: MainChatRuntimeSnapshot,
    timestamp: Option<f64>,
    is_text_event: bool,
) -> MainChatRuntimeSnapshot {
    ensure_direct_stream_defaults(&mut snapshot);
    reset_output(&mut snapshot);
    if let Some(direct) = snapshot.direct_stream.as_mut() {
        direct.has_received_any_event = true;
        direct.initial_retry_count = 0;
        direct.stall_retry_count = 0;
        if is_text_event {
            direct.emitted_first_text = true;
        }
        direct.last_event_at = timestamp.or(direct.last_event_at);
    }
    snapshot
}

pub fn handle_direct_stream_timeout(
    mut snapshot: MainChatRuntimeSnapshot,
    is_initial_poll: bool,
) -> MainChatRuntimeSnapshot {
    ensure_direct_stream_defaults(&mut snapshot);
    reset_output(&mut snapshot);
    let output = snapshot.output.as_mut().expect("output");
    let direct = snapshot.direct_stream.as_mut().expect("direct");
    if is_initial_poll && !direct.has_received_any_event {
        direct.initial_retry_count += 1;
        if direct.initial_retry_count <= direct.max_initial_retries {
            output.should_retry_poll = true;
        } else {
            output.should_finalize_stream = true;
            output.terminal_error = Some(format!(
                "No events received from provider within {}s.",
                direct.first_event_timeout_sec
            ));
        }
        return snapshot;
    }

    direct.stall_retry_count += 1;
    if direct.stall_retry_count <= direct.max_stall_retries {
        output.should_retry_poll = true;
    } else {
        output.should_finalize_stream = true;
        output.terminal_error = Some(format!(
            "Stream stalled: no updates for {}s.",
            direct.activity_timeout_sec
        ));
    }
    snapshot
}

#[cfg(test)]
mod tests {
    use super::{handle_direct_stream_timeout, register_direct_stream_event, start_direct_stream};
    use app_core_protocol::main_chat::MainChatTurnState;
    use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;

    #[test]
    fn initial_timeout_retries_before_failing() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), Some("codex".to_string()));
        let snapshot = handle_direct_stream_timeout(snapshot, true);
        assert_eq!(snapshot.output.as_ref().and_then(|it| it.terminal_error.as_ref()), None);
        assert_eq!(snapshot.output.as_ref().map(|it| it.should_retry_poll), Some(true));
    }

    #[test]
    fn event_received_resets_retry_budgets() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), None);
        let snapshot = handle_direct_stream_timeout(snapshot, true);
        let snapshot = register_direct_stream_event(snapshot, Some(2.0), true);
        let direct = snapshot.direct_stream.expect("direct");
        assert_eq!(direct.initial_retry_count, 0);
        assert_eq!(direct.stall_retry_count, 0);
        assert!(direct.emitted_first_text);
    }

    fn base_snapshot() -> MainChatRuntimeSnapshot {
        MainChatRuntimeSnapshot {
            turn_state: MainChatTurnState {
                conversation_id: "conv".to_string(),
                assistant_message_id: "msg".to_string(),
                turn_id: "turn".to_string(),
                status: "idle".to_string(),
                ..Default::default()
            },
            ..Default::default()
        }
    }
}
