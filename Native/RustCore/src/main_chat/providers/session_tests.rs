use super::session::{
    cancel_session, poll_session, resume_session, start_session, test_session_config_exists,
    test_session_state_exists,
};
use app_core_protocol::main_chat_provider::{
    MainChatProviderBackend, MainChatProviderSessionConfig, MainChatProviderSessionPollRequest,
    MainChatProviderSessionRequest, MainChatProviderSessionStartRequest,
};
use std::path::Path;
use std::thread;
use std::time::Duration;

fn minimal_config(backend: MainChatProviderBackend) -> MainChatProviderSessionConfig {
    MainChatProviderSessionConfig {
        provider_id: "test-provider".to_string(),
        display_name: "Test Provider".to_string(),
        backend,
        workspace_path: ".".to_string(),
        workspace_paths: vec![".".to_string()],
        prompt: "hello".to_string(),
        system_prompt: Some("system".to_string()),
        context_prompt: None,
        model: None,
        api_key: None,
        base_url: None,
        tool_definitions_json: None,
        extra_headers: Default::default(),
        codex_path: None,
        codex_sandbox: None,
        codex_ask_for_approval: None,
        codex_model_override: None,
        codex_reasoning_effort: None,
        codex_model_provider: None,
        codex_fast_mode: false,
        codex_session_full_access: false,
        codex_prefer_responses_wire_api: false,
        claude_path: None,
        claude_model: None,
        claude_allowed_tools: Vec::new(),
        gemini_cli_path: None,
        gemini_model_override: None,
        attachments: Vec::new(),
        cli_accounts: Vec::new(),
    }
}

#[test]
fn cancel_session_marks_snapshot_cancelled() {
    let session_id = "provider-cancel-test".to_string();
    let start = start_session(MainChatProviderSessionStartRequest {
        schema_version: 1,
        session_id: session_id.clone(),
        config: minimal_config(MainChatProviderBackend::OpenaiApi),
    });
    assert!(start.snapshot.is_some());
    assert!(test_session_config_exists(&session_id));
    let cancelled = cancel_session(MainChatProviderSessionRequest {
        schema_version: 1,
        session_id: session_id.clone(),
    });
    assert_eq!(cancelled.snapshot.unwrap().status, "cancelled");
    assert!(!test_session_config_exists(&session_id));
    assert!(!test_session_state_exists(&session_id));
}

#[test]
fn terminal_poll_clears_session_state_and_config() {
    let session_id = "provider-terminal-cleanup-test".to_string();
    let _ = start_session(MainChatProviderSessionStartRequest {
        schema_version: 1,
        session_id: session_id.clone(),
        config: minimal_config(MainChatProviderBackend::OpenaiApi),
    });

    thread::sleep(Duration::from_millis(50));
    let response = poll_session(MainChatProviderSessionPollRequest {
        schema_version: 1,
        session_id: session_id.clone(),
        timeout_ms: 200,
    });

    assert!(response.snapshot.is_some());
    assert!(!test_session_state_exists(&session_id));
    assert!(!test_session_config_exists(&session_id));
}

#[test]
fn missing_cli_path_bubbles_error_into_session_events() {
    if codex_is_detectable() {
        return;
    }
    let session_id = "provider-cli-error-test".to_string();
    let _ = start_session(MainChatProviderSessionStartRequest {
        schema_version: 1,
        session_id: session_id.clone(),
        config: minimal_config(MainChatProviderBackend::CodexCli),
    });
    thread::sleep(Duration::from_millis(50));
    let response = resume_session(MainChatProviderSessionRequest {
        schema_version: 1,
        session_id,
    });
    let snapshot = response.snapshot.unwrap();
    assert_eq!(snapshot.status, "failed");
    assert!(response.events.iter().any(|event| event.kind == app_core_protocol::main_chat_provider::MainChatProviderEventKind::Error));
}

#[test]
fn poll_session_waits_for_terminal_snapshot_without_events() {
    let session_id = "provider-poll-terminal-test".to_string();
    let _ = start_session(MainChatProviderSessionStartRequest {
        schema_version: 1,
        session_id: session_id.clone(),
        config: minimal_config(MainChatProviderBackend::OpenaiApi),
    });
    thread::sleep(Duration::from_millis(50));
    let response = poll_session(MainChatProviderSessionPollRequest {
        schema_version: 1,
        session_id,
        timeout_ms: 200,
    });
    let snapshot = response.snapshot.unwrap();
    assert!(matches!(snapshot.status.as_str(), "completed" | "failed"));
}

fn codex_is_detectable() -> bool {
    find_in_path(std::env::var("PATH").ok().as_deref().unwrap_or(""), "codex")
        || ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .into_iter()
            .any(|path| Path::new(path).is_file())
}

fn find_in_path(path_env: &str, executable: &str) -> bool {
    path_env
        .split(':')
        .filter(|segment| !segment.trim().is_empty())
        .map(|dir| format!("{dir}/{executable}"))
        .any(|candidate| Path::new(&candidate).is_file())
}
