use crate::main_chat::apply_event;
use crate::main_chat::state::{ensure_direct_stream_defaults, reset_output};
use app_core_protocol::main_chat::{MainChatEvent, MainChatEventKind};
use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;
use std::collections::BTreeMap;

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

pub fn apply_direct_stream_provider_event(
    mut snapshot: MainChatRuntimeSnapshot,
    timestamp: Option<f64>,
    provider_id: Option<String>,
    event_kind: Option<&str>,
    payload: BTreeMap<String, String>,
) -> MainChatRuntimeSnapshot {
    let event_kind = event_kind.unwrap_or("other");
    if let Some(provider_id) = provider_id.clone() {
        snapshot.turn_state.provider_id = Some(provider_id);
    }

    snapshot = register_direct_stream_event(
        snapshot,
        timestamp,
        matches!(event_kind, "textDelta" | "textReplace"),
    );

    let Some(main_chat_event_kind) = provider_event_kind(event_kind) else {
        return snapshot;
    };

    let source = provider_id
        .or_else(|| snapshot.turn_state.provider_id.clone())
        .unwrap_or_else(|| "main-chat".to_string());
    let event_timestamp = timestamp.unwrap_or(snapshot.turn_state.updated_at.unwrap_or(0.0));
    let sequence = snapshot.turn_state.sequence + 1;
    let event = MainChatEvent {
        id: format!("{}:{event_kind}:{sequence}", snapshot.turn_state.turn_id),
        conversation_id: snapshot.turn_state.conversation_id.clone(),
        assistant_message_id: snapshot.turn_state.assistant_message_id.clone(),
        turn_id: snapshot.turn_state.turn_id.clone(),
        sequence,
        source,
        kind: main_chat_event_kind,
        payload,
        timestamp: event_timestamp,
    };
    snapshot.turn_state = apply_event(snapshot.turn_state, &event);
    snapshot
}

fn provider_event_kind(event_kind: &str) -> Option<MainChatEventKind> {
    match event_kind {
        "textDelta" => Some(MainChatEventKind::TextDelta),
        "textReplace" => Some(MainChatEventKind::TextReplace),
        "reasoning" => Some(MainChatEventKind::ReasoningDelta),
        "mermaid_render" => Some(MainChatEventKind::MermaidArtifact),
        "command_execution" | "bash" => Some(MainChatEventKind::CommandsArtifact),
        "file_change" | "edit" | "write" | "apply_patch" | "create_file" | "delete_file" => {
            Some(MainChatEventKind::FilesArtifact)
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        apply_direct_stream_provider_event, handle_direct_stream_timeout,
        register_direct_stream_event, start_direct_stream,
    };
    use app_core_protocol::main_chat::MainChatTurnState;
    use app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot;
    use std::collections::BTreeMap;

    #[test]
    fn initial_timeout_retries_before_failing() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), Some("codex".to_string()));
        let snapshot = handle_direct_stream_timeout(snapshot, true);
        assert_eq!(
            snapshot
                .output
                .as_ref()
                .and_then(|it| it.terminal_error.as_ref()),
            None
        );
        assert_eq!(
            snapshot.output.as_ref().map(|it| it.should_retry_poll),
            Some(true)
        );
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

    #[test]
    fn provider_text_delta_updates_turn_state_in_rust() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), Some("codex".to_string()));
        let snapshot = apply_direct_stream_provider_event(
            snapshot,
            Some(2.0),
            Some("codex".to_string()),
            Some("textDelta"),
            BTreeMap::from([
                ("delta".to_string(), "ciao".to_string()),
                ("stream_id".to_string(), "main".to_string()),
            ]),
        );
        let direct = snapshot.direct_stream.expect("direct");
        assert!(direct.has_received_any_event);
        assert!(direct.emitted_first_text);
        assert_eq!(
            snapshot
                .turn_state
                .text_by_stream_id
                .get("main")
                .map(String::as_str),
            Some("ciao")
        );
    }

    #[test]
    fn provider_reasoning_updates_turn_state_in_rust() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), Some("codex".to_string()));
        let snapshot = apply_direct_stream_provider_event(
            snapshot,
            Some(2.0),
            Some("codex".to_string()),
            Some("reasoning"),
            BTreeMap::from([
                ("output".to_string(), "analisi".to_string()),
                ("group_id".to_string(), "reasoning".to_string()),
            ]),
        );
        assert_eq!(
            snapshot
                .turn_state
                .reasoning_by_group_id
                .get("reasoning")
                .map(String::as_str),
            Some("analisi")
        );
    }

    #[test]
    fn provider_raw_file_change_becomes_files_artifact() {
        let snapshot = start_direct_stream(base_snapshot(), Some(1.0), Some("codex".to_string()));
        let snapshot = apply_direct_stream_provider_event(
            snapshot,
            Some(2.0),
            Some("codex".to_string()),
            Some("file_change"),
            BTreeMap::from([("path".to_string(), "App/main.swift".to_string())]),
        );
        assert!(snapshot.turn_state.artifacts.iter().any(|artifact| {
            artifact.kind == app_core_protocol::main_chat::MainChatArtifactKind::Files
                && artifact.items.iter().any(|item| item == "App/main.swift")
        }));
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
