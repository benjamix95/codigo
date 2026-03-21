use crate::main_chat::providers::poll_session;
use crate::main_chat::runtime::handle_runtime_action;
use app_core_protocol::main_chat_provider::{
    MainChatProviderEvent, MainChatProviderEventKind, MainChatProviderSessionPollRequest,
};
use app_core_protocol::main_chat_runtime::{
    MainChatRuntimeActionRequest, MainChatRuntimeProviderPollRequest, MainChatRuntimeProviderPollResponse,
    MainChatRuntimeUIEvent, MainChatRuntimeUIEventKind,
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
    let had_events = !provider_events.is_empty();

    for event in &provider_events {
        runtime_snapshot = reduce_provider_event(runtime_snapshot, &request.provider_id, event);
    }

    let mut is_terminal = false;
    if let Some(snapshot) = session_snapshot {
        match snapshot.status.as_str() {
            "completed" => {
                is_terminal = true;
                runtime_snapshot = complete_runtime(runtime_snapshot);
            }
            "failed" => {
                is_terminal = true;
                runtime_snapshot = fail_runtime(
                    runtime_snapshot,
                    snapshot
                        .terminal_error
                        .as_deref()
                        .unwrap_or("Provider session failed"),
                );
            }
            "cancelled" => {
                is_terminal = true;
                runtime_snapshot = interrupt_runtime(runtime_snapshot);
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
    }

    let ui_events = provider_events.iter().map(ui_event).collect();
    MainChatRuntimeProviderPollResponse::success(
        runtime_snapshot,
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
    let (event_kind, payload, status) = match event.kind {
        MainChatProviderEventKind::Started => return apply_runtime_action(snapshot, "direct_stream_event_received", provider_id, None, None, Default::default()),
        MainChatProviderEventKind::TextDelta => (
            None,
            event.payload.clone(),
            Some("text".to_string()),
        ),
        MainChatProviderEventKind::TextReplace => (
            Some("textReplace".to_string()),
            event.payload.clone(),
            Some("text".to_string()),
        ),
        MainChatProviderEventKind::Raw => (
            Some(event.raw_type.clone().unwrap_or_else(|| "provider_raw".to_string())),
            event.payload.clone(),
            None,
        ),
        MainChatProviderEventKind::Completed => return complete_runtime(snapshot),
        MainChatProviderEventKind::Error => {
            return fail_runtime(snapshot, if event.text.is_empty() { "Provider stream failed" } else { &event.text })
        }
    };

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

    apply_runtime_action(
        snapshot,
        "direct_stream_apply_provider_event",
        provider_id,
        None,
        event_kind,
        payload,
    )
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
    use app_core_protocol::main_chat_runtime::{MainChatRuntimeProviderPollRequest, MainChatRuntimeSnapshot};

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
}
