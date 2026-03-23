use crate::main_chat::providers::poll_session;
use crate::main_chat::runtime::handle_runtime_action;
use app_core_protocol::main_chat_provider::{
    MainChatProviderEvent, MainChatProviderEventKind, MainChatProviderSessionPollRequest,
};
use app_core_protocol::main_chat_runtime::{
    MainChatRuntimeActionRequest, MainChatRuntimeProviderPollRequest, MainChatRuntimeProviderPollResponse,
    MainChatRuntimeSignalKind, MainChatRuntimeUIEvent, MainChatRuntimeUIEventKind,
};

pub fn poll_provider_runtime(
    request: MainChatRuntimeProviderPollRequest,
) -> MainChatRuntimeProviderPollResponse {
    if request.schema_version != 1 {
        return MainChatRuntimeProviderPollResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }

    let session_response = poll_session(MainChatProviderSessionPollRequest {
        schema_version: 1,
        session_id: request.session_id.clone(),
        timeout_ms: request.timeout_ms,
    });
    if let Some(error) = session_response.error {
        return MainChatRuntimeProviderPollResponse::error(&error.code, &error.message);
    }

    let provider_events = session_response.events;
    let session_snapshot = session_response.snapshot;
    let mut runtime_snapshot = request.snapshot;
    let had_any_event = runtime_snapshot
        .direct_stream
        .as_ref()
        .map(|item| item.has_received_any_event)
        .unwrap_or(false);
    let had_first_text = runtime_snapshot
        .direct_stream
        .as_ref()
        .map(|item| item.emitted_first_text)
        .unwrap_or(false);
    let had_events = !provider_events.is_empty();

    for event in &provider_events {
        runtime_snapshot = reduce_provider_event(runtime_snapshot, &request.provider_id, event);
    }

    let mut is_terminal = false;
    let mut signals: Vec<MainChatRuntimeSignalKind> = Vec::new();
    let mut ui_events: Vec<MainChatRuntimeUIEvent> =
        provider_events.iter().map(ui_event).collect();
    if let Some(snapshot) = session_snapshot {
        match snapshot.status.as_str() {
            "completed" => {
                is_terminal = true;
                runtime_snapshot = complete_runtime(runtime_snapshot);
                signals.push(MainChatRuntimeSignalKind::StreamCompleted);
                ui_events.push(MainChatRuntimeUIEvent {
                    kind: MainChatRuntimeUIEventKind::Completed,
                    text: String::new(),
                    raw_type: None,
                    payload: Default::default(),
                });
            }
            "failed" => {
                is_terminal = true;
                let message = snapshot
                    .terminal_error
                    .as_deref()
                    .unwrap_or("Provider session failed")
                    .to_string();
                runtime_snapshot = fail_runtime(
                    runtime_snapshot,
                    &message,
                );
                ui_events.push(MainChatRuntimeUIEvent {
                    kind: MainChatRuntimeUIEventKind::Error,
                    text: message,
                    raw_type: None,
                    payload: Default::default(),
                });
            }
            "cancelled" => {
                is_terminal = true;
                runtime_snapshot = interrupt_runtime(runtime_snapshot);
                signals.push(MainChatRuntimeSignalKind::StreamCompleted);
                ui_events.push(MainChatRuntimeUIEvent {
                    kind: MainChatRuntimeUIEventKind::Completed,
                    text: String::new(),
                    raw_type: None,
                    payload: Default::default(),
                });
            }
            _ => {}
        }
    }

    let did_timeout = !had_events && !is_terminal;
    if did_timeout {
        let is_initial_poll = !runtime_snapshot
            .direct_stream
            .as_ref()
            .map(|item| item.has_received_any_event)
            .unwrap_or(false);
        let response = handle_runtime_action(MainChatRuntimeActionRequest {
            schema_version: 1,
            action: "direct_stream_timeout".to_string(),
            snapshot: runtime_snapshot,
            timestamp: None,
            provider_id: None,
            status: None,
            detail: None,
            text: None,
            questions: None,
            plan_content: None,
            option_full_texts: Vec::new(),
            should_run_inline: None,
            is_initial_poll: Some(is_initial_poll),
            event_kind: None,
            payload: Default::default(),
        });
        runtime_snapshot = match response.runtime_snapshot {
            Some(snapshot) => snapshot,
            None => {
                return MainChatRuntimeProviderPollResponse::error(
                    "runtime_poll_timeout_failed",
                    "Rust runtime timeout handler did not return a snapshot",
                )
            }
        };
        if runtime_snapshot.output.as_ref().map(|item| item.should_retry_poll) != Some(true) {
            is_terminal = true;
            ui_events.push(MainChatRuntimeUIEvent {
                kind: MainChatRuntimeUIEventKind::Error,
                text: runtime_snapshot
                    .output
                    .as_ref()
                    .and_then(|item| item.terminal_error.clone())
                    .unwrap_or_else(|| "Rust main chat direct stream timed out.".to_string()),
                raw_type: None,
                payload: Default::default(),
            });
        }
    }

    let has_any_event = runtime_snapshot
        .direct_stream
        .as_ref()
        .map(|item| item.has_received_any_event)
        .unwrap_or(false);
    let has_first_text = runtime_snapshot
        .direct_stream
        .as_ref()
        .map(|item| item.emitted_first_text)
        .unwrap_or(false);
    if !had_any_event && has_any_event {
        signals.push(MainChatRuntimeSignalKind::FirstEvent);
    }
    if !had_first_text && has_first_text {
        signals.push(MainChatRuntimeSignalKind::FirstTextDelta);
    }

    MainChatRuntimeProviderPollResponse::success(
        runtime_snapshot,
        signals,
        ui_events,
        provider_events,
        is_terminal,
        did_timeout,
    )
}

fn reduce_provider_event(
    snapshot: app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot,
    provider_id: &str,
    event: &MainChatProviderEvent,
) -> app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot {
    let (event_kind, payload, status, use_provider_event_reducer) = match event.kind {
        MainChatProviderEventKind::Started => return apply_runtime_action(snapshot, "direct_stream_event_received", provider_id, None, None, Default::default()),
        MainChatProviderEventKind::TextDelta => (
            Some("textDelta".to_string()),
            event.payload.clone(),
            None,
            true,
        ),
        MainChatProviderEventKind::TextReplace => (
            Some("textReplace".to_string()),
            event.payload.clone(),
            None,
            true,
        ),
        MainChatProviderEventKind::Raw => (
            Some(event.raw_type.clone().unwrap_or_else(|| "provider_raw".to_string())),
            event.payload.clone(),
            None,
            true,
        ),
        MainChatProviderEventKind::Completed => return complete_runtime(snapshot),
        MainChatProviderEventKind::Error => {
            return fail_runtime(snapshot, if event.text.is_empty() { "Provider stream failed" } else { &event.text })
        }
    };

    if use_provider_event_reducer {
        return apply_runtime_action(
            snapshot,
            "direct_stream_apply_provider_event",
            provider_id,
            None,
            event_kind,
            payload,
        );
    }

    if let Some(status) = status {
        return apply_runtime_action(
            snapshot,
            "direct_stream_event_received",
            provider_id,
            Some(status),
            None,
            Default::default(),
        );
    }

    snapshot
}

fn complete_runtime(
    snapshot: app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot,
) -> app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot {
    apply_runtime_action(snapshot, "direct_stream_complete", "", Some("completed".to_string()), None, Default::default())
}

fn fail_runtime(
    snapshot: app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot,
    message: &str,
) -> app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot {
    let response = handle_runtime_action(MainChatRuntimeActionRequest {
        schema_version: 1,
        action: "direct_stream_fail".to_string(),
        snapshot,
        timestamp: None,
        provider_id: None,
        status: Some("failed".to_string()),
        detail: Some(message.to_string()),
        text: None,
        questions: None,
        plan_content: None,
        option_full_texts: Vec::new(),
        should_run_inline: None,
        is_initial_poll: None,
        event_kind: None,
        payload: Default::default(),
    });
    response.runtime_snapshot.unwrap_or_default()
}

fn interrupt_runtime(
    snapshot: app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot,
) -> app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot {
    apply_runtime_action(snapshot, "direct_stream_interrupt", "", Some("cancelled".to_string()), None, Default::default())
}

fn apply_runtime_action(
    snapshot: app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot,
    action: &str,
    provider_id: &str,
    status: Option<String>,
    event_kind: Option<String>,
    payload: std::collections::BTreeMap<String, String>,
) -> app_core_protocol::main_chat_runtime::MainChatRuntimeSnapshot {
    let response = handle_runtime_action(MainChatRuntimeActionRequest {
        schema_version: 1,
        action: action.to_string(),
        snapshot,
        timestamp: None,
        provider_id: if provider_id.is_empty() { None } else { Some(provider_id.to_string()) },
        status,
        detail: None,
        text: None,
        questions: None,
        plan_content: None,
        option_full_texts: Vec::new(),
        should_run_inline: None,
        is_initial_poll: None,
        event_kind,
        payload,
    });
    response.runtime_snapshot.unwrap_or_default()
}

fn ui_event(event: &MainChatProviderEvent) -> MainChatRuntimeUIEvent {
    let kind = match event.kind {
        MainChatProviderEventKind::Started => MainChatRuntimeUIEventKind::Started,
        MainChatProviderEventKind::TextDelta => MainChatRuntimeUIEventKind::TextDelta,
        MainChatProviderEventKind::TextReplace => MainChatRuntimeUIEventKind::TextReplace,
        MainChatProviderEventKind::Raw => MainChatRuntimeUIEventKind::Raw,
        MainChatProviderEventKind::Completed => MainChatRuntimeUIEventKind::Completed,
        MainChatProviderEventKind::Error => MainChatRuntimeUIEventKind::Error,
    };
    MainChatRuntimeUIEvent {
        kind,
        text: event.text.clone(),
        raw_type: event.raw_type.clone(),
        payload: event.payload.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::poll_provider_runtime;
    use crate::main_chat::providers::start_session;
    use app_core_protocol::main_chat_provider::{
        MainChatProviderBackend, MainChatProviderSessionConfig, MainChatProviderSessionStartRequest,
    };
    use app_core_protocol::main_chat_runtime::{
        MainChatRuntimeProviderPollRequest, MainChatRuntimeSignalKind, MainChatRuntimeSnapshot,
        MainChatRuntimeUIEventKind,
    };

    #[test]
    fn poll_provider_runtime_applies_terminal_snapshot_failure() {
        let session_id = "runtime-provider-poll-fail".to_string();
        let _ = start_session(MainChatProviderSessionStartRequest {
            schema_version: 1,
            session_id: session_id.clone(),
            config: MainChatProviderSessionConfig {
                provider_id: "codex-cli".to_string(),
                display_name: "Codex".to_string(),
                backend: MainChatProviderBackend::CodexCli,
                workspace_path: ".".to_string(),
                workspace_paths: vec![".".to_string()],
                prompt: "hello".to_string(),
                ..Default::default()
            },
        });
        let response = poll_provider_runtime(MainChatRuntimeProviderPollRequest {
            schema_version: 1,
            session_id,
            provider_id: "codex-cli".to_string(),
            snapshot: MainChatRuntimeSnapshot::default(),
            timeout_ms: 50,
        });
        assert!(response.runtime_snapshot.is_some());
    }

    #[test]
    fn poll_provider_runtime_applies_text_delta_to_turn_state() {
        use app_core_protocol::main_chat_provider::{
            MainChatProviderEvent, MainChatProviderEventKind,
        };
        use crate::main_chat::providers::append_test_event;
        use crate::main_chat::start_session;

        let session_id = "runtime-provider-poll-delta".to_string();
        let _ = start_session(MainChatProviderSessionStartRequest {
            schema_version: 1,
            session_id: session_id.clone(),
            config: MainChatProviderSessionConfig {
                provider_id: "codex-cli".to_string(),
                display_name: "Codex".to_string(),
                backend: MainChatProviderBackend::CodexCli,
                workspace_path: ".".to_string(),
                workspace_paths: vec![".".to_string()],
                prompt: "hello".to_string(),
                ..Default::default()
            },
        });

        append_test_event(&session_id, MainChatProviderEvent {
            kind: MainChatProviderEventKind::TextDelta,
            text: String::new(),
            raw_type: None,
            payload: std::collections::BTreeMap::from([
                ("delta".to_string(), "ciao".to_string()),
                ("stream_id".to_string(), "main".to_string()),
            ]),
        });

        let response = poll_provider_runtime(MainChatRuntimeProviderPollRequest {
            schema_version: 1,
            session_id,
            provider_id: "codex-cli".to_string(),
            snapshot: MainChatRuntimeSnapshot::default(),
            timeout_ms: 50,
        });
        let snapshot = response.runtime_snapshot.expect("runtime snapshot");
        assert_eq!(
            response.signals,
            vec![
                MainChatRuntimeSignalKind::FirstEvent,
                MainChatRuntimeSignalKind::FirstTextDelta
            ]
        );
        assert_eq!(
            snapshot.turn_state.text_by_stream_id.get("main").map(String::as_str),
            Some("ciao")
        );
    }

    #[test]
    fn poll_provider_runtime_emits_stream_completed_signal_for_cancelled_terminal_snapshot() {
        let session_id = "runtime-provider-poll-cancelled".to_string();
        let _ = start_session(MainChatProviderSessionStartRequest {
            schema_version: 1,
            session_id: session_id.clone(),
            config: MainChatProviderSessionConfig {
                provider_id: "codex-cli".to_string(),
                display_name: "Codex".to_string(),
                backend: MainChatProviderBackend::CodexCli,
                workspace_path: ".".to_string(),
                workspace_paths: vec![".".to_string()],
                prompt: "hello".to_string(),
                ..Default::default()
            },
        });
        let _ = crate::main_chat::providers::cancel_session(
            app_core_protocol::main_chat_provider::MainChatProviderSessionRequest {
                schema_version: 1,
                session_id: session_id.clone(),
            },
        );

        let response = poll_provider_runtime(MainChatRuntimeProviderPollRequest {
            schema_version: 1,
            session_id,
            provider_id: "codex-cli".to_string(),
            snapshot: MainChatRuntimeSnapshot::default(),
            timeout_ms: 50,
        });
        assert!(response
            .signals
            .contains(&MainChatRuntimeSignalKind::StreamCompleted));
        assert!(response
            .ui_events
            .iter()
            .any(|event| event.kind == MainChatRuntimeUIEventKind::Completed));
    }

}
