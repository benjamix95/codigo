use super::api::{anthropic, google, openai};
use super::cli::{claude, codex, gemini};
use super::models::{
    make_completed_event, make_error_event, make_raw_event, make_started_event,
    make_text_delta_event, make_text_replace_event, ProviderSessionHandle,
};
use super::router::{next_cli_account, next_cli_account_after};
use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatProviderBackend, MainChatProviderSessionConfig,
    MainChatProviderSessionPollRequest, MainChatProviderSessionRequest,
    MainChatProviderSessionResponse, MainChatProviderSessionStartRequest,
};
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::Ordering;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

static SESSIONS: OnceLock<Mutex<HashMap<String, ProviderSessionHandle>>> = OnceLock::new();

fn sessions() -> &'static Mutex<HashMap<String, ProviderSessionHandle>> {
    SESSIONS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn is_cancelled(session_id: &str) -> bool {
    let guard = sessions().lock().unwrap();
    guard
        .get(session_id)
        .map(|handle| handle.cancelled.load(Ordering::SeqCst))
        .unwrap_or(false)
}

pub(crate) fn emit_text_delta(session_id: &str, text: &str) {
    push_event(session_id, make_text_delta_event(text.to_string()));
}

pub(crate) fn emit_text_replace(session_id: &str, text: &str) {
    push_event(session_id, make_text_replace_event(text.to_string()));
}

pub(crate) fn emit_raw(session_id: &str, raw_type: &str, payload: BTreeMap<String, String>) {
    push_event(session_id, make_raw_event(raw_type, payload));
}

pub(crate) fn emit_error(session_id: &str, message: &str) {
    push_event(session_id, make_error_event(message.to_string()));
}

pub(crate) fn running_cli_account(
    session_id: &str,
    config: &MainChatProviderSessionConfig,
    _provider: &str,
) -> Result<Option<MainChatCLIAccountSnapshot>, String> {
    if config.cli_accounts.is_empty() {
        return Ok(None);
    }
    let current_id = {
        let guard = sessions().lock().unwrap();
        guard.get(session_id).and_then(|handle| {
            handle
                .snapshot
                .lock()
                .ok()
                .and_then(|snapshot| snapshot.active_account_id.clone())
        })
    };
    let selected = current_id
        .and_then(|id| {
            config
                .cli_accounts
                .iter()
                .find(|item| item.id == id)
                .cloned()
        })
        .or_else(|| next_cli_account(config));
    if let Some(account) = &selected {
        let guard = sessions().lock().unwrap();
        if let Some(handle) = guard.get(session_id) {
            let mut snapshot = handle.snapshot.lock().unwrap();
            snapshot.active_account_id = Some(account.id.clone());
            snapshot.status = "streaming".to_string();
        }
    }
    Ok(selected)
}

pub(crate) fn failover_to_next_cli_account(
    session_id: &str,
    _provider: &str,
    reason: &str,
) -> Result<bool, String> {
    let guard = sessions().lock().unwrap();
    let Some(handle) = guard.get(session_id).cloned() else {
        return Ok(false);
    };
    drop(guard);
    let config = session_config(session_id).ok_or_else(|| "missing_session_config".to_string())?;
    let current_id = handle
        .snapshot
        .lock()
        .unwrap()
        .active_account_id
        .clone()
        .unwrap_or_default();
    let provider = match config.backend {
        MainChatProviderBackend::CodexCli => "codex",
        MainChatProviderBackend::ClaudeCli => "claude",
        MainChatProviderBackend::GeminiCli => "gemini",
        _ => return Ok(false),
    };
    let Some(next) = next_cli_account_after(&config.cli_accounts, provider, &current_id, 0.0)
    else {
        return Ok(false);
    };
    let mut snapshot = handle.snapshot.lock().unwrap();
    snapshot.active_account_id = Some(next.id);
    snapshot.last_failover_reason = Some(reason.to_string());
    Ok(true)
}

pub fn start_session(
    request: MainChatProviderSessionStartRequest,
) -> MainChatProviderSessionResponse {
    if request.schema_version != 1 {
        return MainChatProviderSessionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let handle = ProviderSessionHandle::new(
        request.session_id.clone(),
        request.config.provider_id.clone(),
        request.config.backend.clone(),
    );
    {
        let mut guard = handle.snapshot.lock().unwrap();
        guard.status = "streaming".to_string();
    }
    handle
        .events
        .lock()
        .unwrap()
        .push_back(make_started_event());
    {
        let mut guard = sessions().lock().unwrap();
        guard.insert(request.session_id.clone(), handle.clone());
    }
    store_config(&request.session_id, request.config.clone());
    spawn_worker(request.session_id.clone(), request.config);
    let snapshot = handle.snapshot.lock().unwrap().clone();
    MainChatProviderSessionResponse::success(snapshot, Vec::new())
}

pub fn resume_session(request: MainChatProviderSessionRequest) -> MainChatProviderSessionResponse {
    session_response(request, true)
}

pub fn get_snapshot(request: MainChatProviderSessionRequest) -> MainChatProviderSessionResponse {
    session_response(request, false)
}

pub fn poll_session(
    request: MainChatProviderSessionPollRequest,
) -> MainChatProviderSessionResponse {
    if request.schema_version != 1 {
        return MainChatProviderSessionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let guard = sessions().lock().unwrap();
    let Some(handle) = guard.get(&request.session_id).cloned() else {
        return MainChatProviderSessionResponse::error(
            "missing_session",
            "Provider session not found",
        );
    };
    drop(guard);

    let timeout_ms = request.timeout_ms.max(0) as u64;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let mut backoff_ms = 5_u64;
    let max_backoff_ms = 50_u64;

    loop {
        let snapshot = handle.snapshot.lock().unwrap().clone();
        let mut queue = handle.events.lock().unwrap();
        if !queue.is_empty() {
            let events = queue.drain(..).collect();
            let terminal = matches!(
                snapshot.status.as_str(),
                "completed" | "failed" | "cancelled"
            );
            drop(queue);
            if terminal {
                cleanup_session_state(&request.session_id);
            }
            return MainChatProviderSessionResponse::success(snapshot, events);
        }
        drop(queue);

        if matches!(
            snapshot.status.as_str(),
            "completed" | "failed" | "cancelled"
        ) {
            cleanup_session_state(&request.session_id);
            return MainChatProviderSessionResponse::success(snapshot, Vec::new());
        }

        if Instant::now() >= deadline {
            return MainChatProviderSessionResponse::success(snapshot, Vec::new());
        }

        thread::sleep(Duration::from_millis(backoff_ms));
        backoff_ms = (backoff_ms.saturating_mul(2)).min(max_backoff_ms);
    }
}

pub fn cancel_session(request: MainChatProviderSessionRequest) -> MainChatProviderSessionResponse {
    if request.schema_version != 1 {
        return MainChatProviderSessionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let guard = sessions().lock().unwrap();
    let Some(handle) = guard.get(&request.session_id).cloned() else {
        return MainChatProviderSessionResponse::error(
            "missing_session",
            "Provider session not found",
        );
    };
    drop(guard);
    handle.cancelled.store(true, Ordering::SeqCst);
    handle
        .events
        .lock()
        .unwrap()
        .push_back(make_completed_event());
    {
        let mut snapshot = handle.snapshot.lock().unwrap();
        snapshot.status = "cancelled".to_string();
        snapshot.terminal_error = Some("cancelled".to_string());
    }
    let snapshot = handle.snapshot.lock().unwrap().clone();
    // NOTE: do NOT call cleanup_session_state here — the next poll_session
    // call will see the terminal "cancelled" status, emit StreamCompleted,
    // and clean up.  Cleaning up eagerly causes poll to get "missing_session"
    // instead of the terminal snapshot.
    MainChatProviderSessionResponse::success(snapshot, Vec::new())
}

fn session_response(
    request: MainChatProviderSessionRequest,
    consume_events: bool,
) -> MainChatProviderSessionResponse {
    if request.schema_version != 1 {
        return MainChatProviderSessionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let guard = sessions().lock().unwrap();
    let Some(handle) = guard.get(&request.session_id).cloned() else {
        return MainChatProviderSessionResponse::error(
            "missing_session",
            "Provider session not found",
        );
    };
    drop(guard);
    let snapshot = handle.snapshot.lock().unwrap().clone();
    let events = if consume_events {
        let mut queue = handle.events.lock().unwrap();
        queue.drain(..).collect()
    } else {
        Vec::new()
    };
    let terminal = matches!(
        snapshot.status.as_str(),
        "completed" | "failed" | "cancelled"
    );
    if terminal && (consume_events || events.is_empty()) {
        cleanup_session_state(&request.session_id);
    }
    MainChatProviderSessionResponse::success(snapshot, events)
}

fn spawn_worker(session_id: String, config: MainChatProviderSessionConfig) {
    thread::spawn(move || {
        // Wrap the entire worker in catch_unwind so that a Rust panic
        // (e.g. debug assertions on broken-pipe data) is converted to an
        // error instead of crashing the host Swift process.
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            match config.backend {
                MainChatProviderBackend::OpenaiApi => openai::run(&session_id, &config),
                MainChatProviderBackend::GoogleApi => google::run(&session_id, &config),
                MainChatProviderBackend::AnthropicApi => anthropic::run(&session_id, &config),
                MainChatProviderBackend::CodexCli => {
                    retry_cli(&session_id, &config, MainChatProviderBackend::CodexCli)
                }
                MainChatProviderBackend::ClaudeCli => {
                    retry_cli(&session_id, &config, MainChatProviderBackend::ClaudeCli)
                }
                MainChatProviderBackend::GeminiCli => {
                    retry_cli(&session_id, &config, MainChatProviderBackend::GeminiCli)
                }
            }
        }));

        let result = match result {
            Ok(inner) => inner,
            Err(_) => Err("worker_panic: internal panic caught in provider worker thread".to_string()),
        };

        let guard = sessions().lock().unwrap();
        if let Some(handle) = guard.get(&session_id) {
            let mut snapshot = handle.snapshot.lock().unwrap();
            match result {
                Ok(()) if snapshot.status != "cancelled" => {
                    snapshot.status = "completed".to_string();
                    handle
                        .events
                        .lock()
                        .unwrap()
                        .push_back(make_completed_event());
                }
                Ok(()) => {}
                Err(ref error) if error == "cancelled" => {
                    snapshot.status = "cancelled".to_string();
                }
                Err(error) => {
                    snapshot.status = "failed".to_string();
                    snapshot.terminal_error = Some(error.clone());
                    handle
                        .events
                        .lock()
                        .unwrap()
                        .push_back(make_error_event(error));
                }
            }
        }
    });
}

fn retry_cli(
    session_id: &str,
    config: &MainChatProviderSessionConfig,
    backend: MainChatProviderBackend,
) -> Result<(), String> {
    loop {
        let result = match backend {
            MainChatProviderBackend::CodexCli => codex::run(session_id, config),
            MainChatProviderBackend::ClaudeCli => claude::run(session_id, config),
            MainChatProviderBackend::GeminiCli => gemini::run(session_id, config),
            _ => Ok(()),
        };
        match result {
            Err(error) if error == "retry_with_next_account" => continue,
            other => return other,
        }
    }
}

fn push_event(
    session_id: &str,
    event: app_core_protocol::main_chat_provider::MainChatProviderEvent,
) {
    let guard = sessions().lock().unwrap();
    if let Some(handle) = guard.get(session_id) {
        if let Ok(mut snapshot) = handle.snapshot.lock() {
            snapshot.emitted_event_count += 1;
        }
        handle.events.lock().unwrap().push_back(event);
    }
}

fn cleanup_session_state(session_id: &str) {
    sessions().lock().unwrap().remove(session_id);
    config_store().lock().unwrap().remove(session_id);
}

static CONFIGS: OnceLock<Mutex<HashMap<String, MainChatProviderSessionConfig>>> = OnceLock::new();

fn config_store() -> &'static Mutex<HashMap<String, MainChatProviderSessionConfig>> {
    CONFIGS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn store_config(session_id: &str, config: MainChatProviderSessionConfig) {
    config_store()
        .lock()
        .unwrap()
        .insert(session_id.to_string(), config);
}

fn session_config(session_id: &str) -> Option<MainChatProviderSessionConfig> {
    config_store().lock().unwrap().get(session_id).cloned()
}

#[cfg(test)]
pub(crate) fn append_test_event(
    session_id: &str,
    event: app_core_protocol::main_chat_provider::MainChatProviderEvent,
) {
    push_event(session_id, event);
}

#[cfg(test)]
pub(crate) fn test_session_state_exists(session_id: &str) -> bool {
    sessions().lock().unwrap().contains_key(session_id)
}

#[cfg(test)]
pub(crate) fn test_session_config_exists(session_id: &str) -> bool {
    config_store().lock().unwrap().contains_key(session_id)
}
