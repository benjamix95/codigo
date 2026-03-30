use super::codex_app_server_prompt::merged_codex_base_instructions;
use super::codex_app_server_mcp_status::{
    codex_mcp_startup_status_payload, codex_required_mcp_startup_failure,
    parse_codex_mcp_startup_status,
};
use super::codex_app_server_subagent_lifecycle::is_subagent_launch_ack_payload;
use super::codex_app_server_support::{
    enrich_codex_process_error, first_result_text, flatten_app_server_params_to_payload,
    is_turn_completed, json_rpc_id, normalize_status, raw_string_field, send_error,
    send_notification, send_request, send_result, spawn_stderr_collector,
};
use super::codex_app_server_tool_search::CodexToolSearchEmitter;
use crate::main_chat::providers::common::string_value;
use crate::main_chat::providers::session::{emit_error, emit_raw, emit_text_delta, is_cancelled};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::process::{Child, ChildStdin, Command, Stdio};

fn rust_codex_trace_enabled() -> bool {
    matches!(
        std::env::var("SOLOCODE_STREAM_TRACE")
            .ok()
            .map(|value| value.to_lowercase()),
        Some(value) if value == "1" || value == "true"
    )
}

fn rust_codex_trace(message: impl AsRef<str>) {
    if rust_codex_trace_enabled() {
        crate::provider_stderr_eprintln!("[RustCodexTrace] {}", message.as_ref());
    }
}

struct ChildProcessGuard {
    child: Option<Child>,
}

impl ChildProcessGuard {
    fn new(child: Child) -> Self {
        Self { child: Some(child) }
    }

    fn child_mut(&mut self) -> Result<&mut Child, String> {
        self.child
            .as_mut()
            .ok_or_else(|| "codex_app_server_missing_child".to_string())
    }
}

impl Drop for ChildProcessGuard {
    fn drop(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[derive(Default)]
struct CodexAgentMessageGate {
    /// Testo visibile nella timeline assistant (`text_delta` / `assistant_update` "output").
    /// Deve includere anche i preamboli `commentary`, non solo la final answer.
    visible_timeline_text: String,
    /// `phase` dell’item `agentMessage` da `item/started` (le delta spesso non la ripetono).
    agent_message_phase_by_item_id: HashMap<String, String>,
    /// Parser incrementale delle righe `select:...` emesse dal runtime Codex durante la selection dei tool.
    tool_search_emitter: CodexToolSearchEmitter,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CodexAgentMessagePhaseKind {
    Commentary,
    FinalAnswer,
}

impl CodexAgentMessageGate {
    fn classify_agent_phase(phase: Option<&str>) -> CodexAgentMessagePhaseKind {
        match phase.map(|p| p.trim().to_lowercase()).as_deref() {
            Some("commentary") => CodexAgentMessagePhaseKind::Commentary,
            _ => CodexAgentMessagePhaseKind::FinalAnswer,
        }
    }

    fn record_agent_message_item_started(&mut self, item_id: String, phase: String) {
        self.agent_message_phase_by_item_id.insert(item_id, phase);
    }

    fn clear_agent_message_item(&mut self, item_id: &str) {
        self.agent_message_phase_by_item_id.remove(item_id);
    }

    /// Risolve `phase` per una delta: campo sul payload, altrimenti ultimo valore da `item/started` / delta precedente.
    fn resolve_agent_message_phase_for_delta_payload(&self, payload: &Value) -> Option<String> {
        if let Some(p) = payload.get("phase").and_then(string_value) {
            return Some(p);
        }
        payload
            .get("itemId")
            .and_then(string_value)
            .and_then(|id| self.agent_message_phase_by_item_id.get(&id).cloned())
    }

    /// Aggiorna la mappa quando una delta (o started) riporta esplicitamente `phase`.
    fn refresh_agent_message_phase_from_delta_payload(&mut self, payload: &Value) {
        if let (Some(id), Some(ph)) = (
            payload.get("itemId").and_then(string_value),
            payload.get("phase").and_then(string_value),
        ) {
            self.agent_message_phase_by_item_id.insert(id, ph);
        }
    }

    /// Delta `item/agentMessage/delta`: commentary vs risposta utente (final).
    fn push_agent_message_delta(
        &mut self,
        delta: &str,
        phase: Option<&str>,
    ) -> Option<(CodexAgentMessagePhaseKind, String)> {
        if delta.is_empty() {
            return None;
        }
        let kind = Self::classify_agent_phase(phase);
        self.visible_timeline_text.push_str(delta);
        Some((kind, delta.to_string()))
    }

    fn cumulative_text(&self) -> String {
        self.visible_timeline_text.clone()
    }
    fn release_after_operational_event(&mut self) -> Option<String> {
        None
    }

    fn flush_pending(&mut self) -> Option<String> {
        None
    }

    fn extract_tool_search_from_delta(&mut self, delta: &str) -> Vec<BTreeMap<String, String>> {
        self.tool_search_emitter.consume_delta(delta)
    }

    fn extract_tool_search_from_completed_text(
        &mut self,
        text: &str,
    ) -> Vec<BTreeMap<String, String>> {
        self.tool_search_emitter.consume_completed_text(text)
    }
}

pub(crate) fn run(
    session_id: &str,
    config: &MainChatProviderSessionConfig,
    executable: &str,
    environment: &BTreeMap<String, String>,
) -> Result<(), String> {
    let process = Command::new(executable)
        .arg("app-server")
        .current_dir(&config.workspace_path)
        .envs(environment)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("codex_app_server_spawn_failed:{error}"))?;
    let mut process = ChildProcessGuard::new(process);

    let mut stdin = process
        .child_mut()?
        .stdin
        .take()
        .ok_or_else(|| "codex_app_server_missing_stdin".to_string())?;
    let stdout = process
        .child_mut()?
        .stdout
        .take()
        .ok_or_else(|| "codex_app_server_missing_stdout".to_string())?;
    let stderr = process
        .child_mut()?
        .stderr
        .take()
        .ok_or_else(|| "codex_app_server_missing_stderr".to_string())?;
    let stderr_tail = spawn_stderr_collector(stderr);
    let mut reader = BufReader::new(stdout);

    let outcome = (|| -> Result<(), String> {
        // Allineato a https://developers.openai.com/codex/app-server (initialize + experimentalApi).
        send_request(
            &mut stdin,
            1,
            "initialize",
            json!({
                "clientInfo": {
                    "name": "solocode",
                    "title": "Solo Code",
                    "version": env!("CARGO_PKG_VERSION")
                },
                "capabilities": {
                    "experimentalApi": true
                }
            }),
        )?;
        send_notification(&mut stdin, "notifications/initialized", json!({}))?;
        send_request(&mut stdin, 2, "config/mcpServer/reload", Value::Null)?;
        let thread_id = wait_for_thread_start(session_id, config, &mut stdin, &mut reader)?;
        start_turn(session_id, config, &thread_id, &mut stdin, &mut reader)?;
        stream_until_turn_completed(session_id, &mut stdin, &mut reader)
    })();

    match outcome {
        Ok(()) => Ok(()),
        Err(err) => {
            let child = process.child_mut()?;
            Err(enrich_codex_process_error(err, &stderr_tail, child))
        }
    }
}

fn wait_for_thread_start(
    session_id: &str,
    config: &MainChatProviderSessionConfig,
    stdin: &mut ChildStdin,
    reader: &mut BufReader<std::process::ChildStdout>,
) -> Result<String, String> {
    let mut gate = CodexAgentMessageGate::default();
    send_request(stdin, 3, "thread/start", thread_start_params(config))?;
    loop {
        if is_cancelled(session_id) {
            return Err("cancelled".to_string());
        }
        let value = read_json_line(reader)?;
        if let Some(thread_id) = handle_response_id(&value, 3)?.and_then(|result| {
            result
                .get("thread")
                .and_then(|thread| thread.get("id"))
                .and_then(string_value)
        }) {
            return Ok(thread_id);
        }
        handle_message(session_id, stdin, &value, &mut gate)?;
    }
}

fn start_turn(
    session_id: &str,
    config: &MainChatProviderSessionConfig,
    thread_id: &str,
    stdin: &mut ChildStdin,
    reader: &mut BufReader<std::process::ChildStdout>,
) -> Result<(), String> {
    let mut gate = CodexAgentMessageGate::default();
    send_request(
        stdin,
        4,
        "turn/start",
        json!({
            "threadId": thread_id,
            "input": turn_input(config),
            "cwd": config.workspace_path,
            "approvalPolicy": config.codex_ask_for_approval.clone().unwrap_or_else(|| "never".to_string())
        }),
    )?;
    loop {
        if is_cancelled(session_id) {
            return Err("cancelled".to_string());
        }
        let value = read_json_line(reader)?;
        if handle_response_id(&value, 4)?.is_some() {
            return Ok(());
        }
        handle_message(session_id, stdin, &value, &mut gate)?;
    }
}

fn stream_until_turn_completed(
    session_id: &str,
    stdin: &mut ChildStdin,
    reader: &mut BufReader<std::process::ChildStdout>,
) -> Result<(), String> {
    let mut gate = CodexAgentMessageGate::default();
    loop {
        if is_cancelled(session_id) {
            return Err("cancelled".to_string());
        }
        let value = read_json_line(reader)?;
        if is_turn_completed(&value) {
            if let Some(buffered) = gate.flush_pending() {
                emit_text_delta(session_id, &buffered);
            }
            emit_raw(session_id, "turn_completed", BTreeMap::new());
            return Ok(());
        }
        handle_message(session_id, stdin, &value, &mut gate)?;
    }
}

fn handle_message(
    session_id: &str,
    stdin: &mut ChildStdin,
    value: &Value,
    gate: &mut CodexAgentMessageGate,
) -> Result<(), String> {
    if let Some(method) = value.get("method").and_then(string_value) {
        if value.get("id").is_some() {
            return handle_server_request(stdin, value, &method);
        }
        return handle_notification(session_id, value, &method, gate);
    }
    if let Some(error) = value
        .get("error")
        .and_then(|item| item.get("message"))
        .and_then(string_value)
    {
        emit_error(session_id, &error);
        return Err(error);
    }
    Ok(())
}

fn handle_notification(
    session_id: &str,
    value: &Value,
    method: &str,
    gate: &mut CodexAgentMessageGate,
) -> Result<(), String> {
    let payload = value.get("params").cloned().unwrap_or(Value::Null);
    rust_codex_trace(format!(
        "notification method={method} payload_keys={}",
        payload
            .as_object()
            .map(|map| map.keys().cloned().collect::<Vec<_>>().join(","))
            .unwrap_or_default()
    ));
    match method {
        "turn/started" => {
            rust_codex_trace("emit raw turn_started");
            emit_raw(session_id, "turn_started", BTreeMap::new())
        }
        "error" => {
            let message = payload
                .get("message")
                .and_then(string_value)
                .unwrap_or_else(|| "app_server_error".to_string());
            emit_error(session_id, &message);
            return Err(message);
        }
        "item/agentMessage/delta" => {
            if let Some(delta) = raw_string_field(&payload, "delta") {
                let phase = gate.resolve_agent_message_phase_for_delta_payload(&payload);
                rust_codex_trace(format!(
                    "agent delta chars={} phase={}",
                    delta.len(),
                    phase.as_deref().unwrap_or("")
                ));
                if let Some((_kind, visible_delta)) =
                    gate.push_agent_message_delta(&delta, phase.as_deref())
                {
                    rust_codex_trace(format!("emit text_delta chars={}", visible_delta.len()));
                    emit_text_delta(session_id, &visible_delta);
                }
                // App-server documenta `item/*/delta` come stream incrementale
                // e `item/completed` come stato finale autorevole: la timeline testo
                // passa da `text_delta`; gli `assistant_update` restano su
                // `item/started` e `item/completed`.
                gate.refresh_agent_message_phase_from_delta_payload(&payload);
                for tool_search_payload in gate.extract_tool_search_from_delta(&delta) {
                    emit_raw(session_id, "tool_search", tool_search_payload);
                }
            }
        }
        "item/reasoning/textDelta" | "item/reasoning/summaryTextDelta" => {
            if let Some(delta) = raw_string_field(&payload, "delta") {
                rust_codex_trace(format!("drop reasoning delta chars={}", delta.len()));
            }
        }
        "item/reasoning/summaryPartAdded" => {
            rust_codex_trace("drop reasoning summaryPartAdded");
        }
        "item/plan/delta" => {
            if let Some(delta) = raw_string_field(&payload, "delta") {
                rust_codex_trace(format!("plan delta chars={}", delta.len()));
                let item_id = payload
                    .get("itemId")
                    .and_then(string_value)
                    .unwrap_or_default();
                let group_id = if item_id.is_empty() {
                    "codex-plan-stream".to_string()
                } else {
                    format!("codex-plan-{item_id}")
                };
                emit_raw(
                    session_id,
                    "reasoning",
                    BTreeMap::from([
                        ("output".to_string(), delta),
                        ("title".to_string(), "Plan".to_string()),
                        ("group_id".to_string(), group_id),
                    ]),
                );
            }
        }
        "turn/plan/updated" => {
            let mut m = BTreeMap::new();
            if let Some(ex) = payload.get("explanation").and_then(string_value) {
                m.insert("explanation".to_string(), codex_truncate_str(&ex, 4_000));
            }
            if let Some(plan) = payload.get("plan") {
                if let Ok(s) = serde_json::to_string(plan) {
                    m.insert("plan_json".to_string(), codex_truncate_str(&s, 12_000));
                }
            }
            if let Some(tid) = payload.get("turnId").and_then(string_value) {
                m.insert("turn_id".to_string(), tid);
            }
            if !m.is_empty() {
                emit_raw(session_id, "turn_plan_updated", m);
            }
        }
        // Documentati in https://developers.openai.com/codex/app-server (Events)
        "thread/tokenUsage/updated" => {
            let mut m = flatten_app_server_params_to_payload(&payload, 8_000);
            m.entry("title".to_string())
                .or_insert_with(|| "Token usage".to_string());
            m.entry("detail".to_string())
                .or_insert_with(|| "Aggiornamento utilizzo token (thread)".to_string());
            emit_raw(session_id, "codex_thread_token_usage", m);
        }
        "thread/status/changed" => {
            let mut m = flatten_app_server_params_to_payload(&payload, 4_000);
            m.entry("title".to_string())
                .or_insert_with(|| "Thread status".to_string());
            emit_raw(session_id, "codex_thread_status", m);
        }
        "account/rateLimits/updated" => {
            let mut m = flatten_app_server_params_to_payload(&payload, 8_000);
            m.entry("title".to_string())
                .or_insert_with(|| "Rate limits".to_string());
            emit_raw(session_id, "codex_rate_limits_updated", m);
        }
        "mcpServer/startupStatus/updated" => {
            if let Some(status) = parse_codex_mcp_startup_status(&payload) {
                emit_raw(
                    session_id,
                    "codex_mcp_server_status",
                    codex_mcp_startup_status_payload(&status),
                );
                if let Some(message) = codex_required_mcp_startup_failure(&status) {
                    emit_error(session_id, &message);
                    return Err(message);
                }
            }
        }
        "turn/diff/updated" => {
            let mut m = flatten_app_server_params_to_payload(&payload, 24_000);
            m.entry("title".to_string())
                .or_insert_with(|| "Diff turn".to_string());
            emit_raw(session_id, "codex_turn_diff", m);
        }
        "item/started" | "item/completed" => {
            handle_item_notification(session_id, method, &payload, gate)
        }
        _ => {}
    }
    Ok(())
}

fn handle_item_notification(
    session_id: &str,
    method: &str,
    payload: &Value,
    gate: &mut CodexAgentMessageGate,
) {
    let item = payload.get("item").cloned().unwrap_or(Value::Null);
    let item_type = item.get("type").and_then(string_value).unwrap_or_default();
    if item_type == "mcpToolCall" {
        emit_mcp_events(session_id, method, &item);
        let tool = item.get("tool").and_then(string_value).unwrap_or_default();
        if is_operational_mcp_tool(&tool) {
            if let Some(buffered) = gate.release_after_operational_event() {
                emit_text_delta(session_id, &buffered);
            }
        }
    } else if item_type == "commandExecution" {
        emit_command_execution(session_id, method, &item);
        if let Some(buffered) = gate.release_after_operational_event() {
            emit_text_delta(session_id, &buffered);
        }
    } else if item_type == "collabToolCall" {
        emit_collab_tool_call(session_id, method, &item);
        if let Some(buffered) = gate.release_after_operational_event() {
            emit_text_delta(session_id, &buffered);
        }
    } else if item_type == "fileChange" {
        emit_file_change(session_id, method, &item);
        if let Some(buffered) = gate.release_after_operational_event() {
            emit_text_delta(session_id, &buffered);
        }
    } else if item_type == "agentMessage" {
        if method == "item/started" {
            if let (Some(id), Some(ph)) = (
                item.get("id").and_then(string_value),
                item.get("phase").and_then(string_value),
            ) {
                gate.record_agent_message_item_started(id, ph);
            }
        }
        let phase = item.get("phase").and_then(string_value);
        if method == "item/completed" {
            if let Some(id) = item.get("id").and_then(string_value) {
                gate.clear_agent_message_item(&id);
            }
            let mut card = BTreeMap::new();
            if let Some(p) = phase {
                let phase_kind = match CodexAgentMessageGate::classify_agent_phase(Some(&p)) {
                    CodexAgentMessagePhaseKind::Commentary => "commentary",
                    CodexAgentMessagePhaseKind::FinalAnswer => "final_answer",
                };
                card.insert("phase".to_string(), p);
                card.insert("phase_kind".to_string(), phase_kind.to_string());
            }
            if let Some(text) = item.get("text").and_then(string_value) {
                for tool_search_payload in gate.extract_tool_search_from_completed_text(&text) {
                    emit_raw(session_id, "tool_search", tool_search_payload);
                }
                card.insert("output".to_string(), codex_truncate_str(&text, 2_000));
            }
            card.insert("lifecycle".to_string(), "completed".to_string());
            card.insert("title".to_string(), "Agent message".to_string());
            emit_raw(session_id, "assistant_update", card);
        } else if let Some(p) = phase {
            let phase_kind = match CodexAgentMessageGate::classify_agent_phase(Some(&p)) {
                CodexAgentMessagePhaseKind::Commentary => "commentary",
                CodexAgentMessagePhaseKind::FinalAnswer => "final_answer",
            };
            emit_raw(
                session_id,
                "assistant_update",
                BTreeMap::from([
                    ("phase".to_string(), p),
                    ("phase_kind".to_string(), phase_kind.to_string()),
                    ("lifecycle".to_string(), "started".to_string()),
                    ("title".to_string(), "Agent message".to_string()),
                ]),
            );
        }
    } else if item_type == "reasoning" {
        rust_codex_trace("drop reasoning item");
    } else if item_type == "contextCompaction" {
        let mut card = BTreeMap::from([
            ("title".to_string(), "Context compaction".to_string()),
            ("type".to_string(), "context_compaction".to_string()),
        ]);
        if let Some(id) = item.get("id").and_then(string_value) {
            card.insert("id".to_string(), id);
        }
        card.insert(
            "lifecycle".to_string(),
            if method == "item/completed" {
                "completed"
            } else {
                "started"
            }
            .to_string(),
        );
        emit_raw(session_id, "codex_context_compaction", card);
    } else if item_type == "plan" {
        let mut card = BTreeMap::from([("title".to_string(), "Plan".to_string())]);
        if let Some(id) = item.get("id").and_then(string_value) {
            card.insert("group_id".to_string(), format!("codex-plan-{id}"));
        }
        if let Some(text) = item.get("text").and_then(string_value) {
            card.insert("output".to_string(), codex_truncate_str(&text, 12_000));
        }
        if method == "item/completed" {
            card.insert("lifecycle".to_string(), "completed".to_string());
        }
        if card.contains_key("output") {
            emit_raw(session_id, "reasoning", card);
        }
    }
}

fn emit_file_change(session_id: &str, method: &str, item: &Value) {
    let id = item.get("id").and_then(string_value).unwrap_or_default();
    let file_path = item
        .get("filePath")
        .or_else(|| item.get("file"))
        .and_then(string_value)
        .unwrap_or_default();
    let is_completed = method == "item/completed";
    let mut payload = BTreeMap::new();
    payload.insert("id".to_string(), id);
    payload.insert("type".to_string(), "file_change".to_string());
    payload.insert("name".to_string(), "edit".to_string());
    payload.insert("path".to_string(), file_path.clone());
    payload.insert("file".to_string(), file_path);
    payload.insert(
        "status".to_string(),
        if is_completed {
            "completed".to_string()
        } else {
            "running".to_string()
        },
    );
    // Extract line counts if available
    if let Some(added) = item.get("linesAdded").and_then(string_value) {
        payload.insert("linesAdded".to_string(), added);
    }
    if let Some(removed) = item.get("linesRemoved").and_then(string_value) {
        payload.insert("linesRemoved".to_string(), removed);
    }
    emit_raw(session_id, "file_change", payload);
}

/// Handle native Codex subagent events (`collabToolCall` item type).
/// These represent the App Server's native multi-agent coordination —
/// a parent agent delegates work to a child thread.
fn emit_collab_tool_call(session_id: &str, method: &str, item: &Value) {
    let id = item.get("id").and_then(string_value).unwrap_or_default();
    let tool = item.get("tool").and_then(string_value).unwrap_or_default();
    let prompt = item
        .get("prompt")
        .and_then(string_value)
        .unwrap_or_default();
    let sender_thread = item
        .get("senderThreadId")
        .and_then(string_value)
        .unwrap_or_default();
    let new_thread = item
        .get("newThreadId")
        .or_else(|| item.get("receiverThreadId"))
        .and_then(string_value)
        .unwrap_or_default();
    let agent_status = item
        .get("agentStatus")
        .and_then(string_value)
        .unwrap_or_default();
    let is_completed = method == "item/completed";

    // Derive a human-readable agent name from the tool or prompt
    let agent_label = if !tool.is_empty() {
        tool.strip_prefix("coderide_subagent_")
            .or_else(|| tool.strip_prefix("coderide_"))
            .unwrap_or(&tool)
            .to_string()
    } else if !prompt.is_empty() {
        let preview_end = prompt
            .char_indices()
            .nth(50)
            .map_or(prompt.len(), |(i, _)| i);
        prompt[..preview_end].to_string()
    } else {
        "Sub Agent".to_string()
    };

    // Extract role name from tool
    let role_name = codex_subagent_role_name(&tool);
    // Generate readable name from prompt
    let readable = codex_readable_name(&prompt, &agent_label);
    // Unique swarm_id per sub-agent — internal, never shown to user
    let unique_key = if !id.is_empty() { &id } else { &new_thread };
    let unique_swarm_id = codex_make_swarm_id(unique_key);

    let status = if is_completed { "completed" } else { "running" };
    let title = if is_completed {
        format!(
            "{} — {}",
            readable,
            if agent_status.is_empty() {
                "completed"
            } else {
                &agent_status
            }
        )
    } else {
        readable.clone()
    };

    let mut payload = BTreeMap::new();
    payload.insert(
        "id".to_string(),
        if !id.is_empty() {
            id
        } else {
            new_thread.clone()
        },
    );
    payload.insert("status".to_string(), status.to_string());
    payload.insert("agent_name".to_string(), agent_label);
    payload.insert("readable_name".to_string(), readable);
    payload.insert("role".to_string(), role_name);
    payload.insert("title".to_string(), title);
    payload.insert("swarm_id".to_string(), unique_swarm_id.clone());
    payload.insert("group_id".to_string(), format!("swarm-{}", unique_swarm_id));
    if !sender_thread.is_empty() {
        payload.insert("sender_thread_id".to_string(), sender_thread);
    }
    if !new_thread.is_empty() {
        payload.insert("thread_id".to_string(), new_thread);
    }
    if !prompt.is_empty() {
        let text_preview = codex_truncate_str(&prompt, 500);
        payload.insert("task_summary".to_string(), text_preview.clone());
        payload.insert("text".to_string(), text_preview.clone());
        payload.insert("description".to_string(), text_preview);
    }

    crate::provider_stderr_eprintln!(
        "[CODEX_DEBUG] collabToolCall: method={} status={} agent={}",
        method,
        status,
        payload.get("readable_name").cloned().unwrap_or_default()
    );
    emit_raw(session_id, "agent", payload);
}

fn is_operational_mcp_tool(tool: &str) -> bool {
    let normalized = tool.strip_prefix("coderide_").unwrap_or(tool).trim();
    !normalized.is_empty() && normalized != "policy_ack"
}

fn emit_mcp_events(session_id: &str, method: &str, item: &Value) {
    let mut payload = BTreeMap::new();
    let server = item
        .get("server")
        .and_then(string_value)
        .unwrap_or_default();
    let tool = item.get("tool").and_then(string_value).unwrap_or_default();
    let status = item
        .get("status")
        .and_then(string_value)
        .unwrap_or_else(|| {
            if method.ends_with("started") {
                "started".to_string()
            } else {
                "completed".to_string()
            }
        });
    if let Some(id) = item.get("id").and_then(string_value) {
        payload.insert("id".to_string(), id.clone());
        payload.insert("tool_call_id".to_string(), id);
    }
    if !server.is_empty() {
        payload.insert("mcp_server".to_string(), server.clone());
        payload.insert("server_id".to_string(), server);
    }
    if !tool.is_empty() {
        payload.insert("mcp_tool".to_string(), tool.clone());
        payload.insert("tool".to_string(), tool.clone());
    }
    payload.insert("status".to_string(), normalize_status(&status));
    if let Some(arguments) = item.get("arguments").and_then(Value::as_object) {
        for (key, value) in arguments {
            if let Some(text) = string_value(value) {
                payload.insert(key.clone(), text);
            }
        }
    }
    if let Some(result_text) = first_result_text(item.get("result")) {
        payload.insert("output".to_string(), result_text);
    }
    if let Some(error_text) = item.get("error").and_then(string_value) {
        payload.insert("error".to_string(), error_text);
    }
    rust_codex_trace(format!(
        "emit mcp_tool_call method={} tool={} status={} keys={}",
        method,
        tool,
        payload.get("status").cloned().unwrap_or_default(),
        payload.keys().cloned().collect::<Vec<_>>().join(",")
    ));
    emit_raw(session_id, "mcp_tool_call", payload.clone());

    // Detect coderide subagent tools and emit an `agent` event so the
    // SwarmLiveReducer creates visible subagent cards in the chat.
    if tool.contains("subagent_") {
        if payload.get("status").map(String::as_str) == Some("completed")
            && is_subagent_launch_ack_payload(&payload)
        {
            return;
        }
        let agent_label = tool
            .strip_prefix("coderide_subagent_")
            .unwrap_or(&tool)
            .to_string();
        let role_name = codex_subagent_role_name(&tool);
        let is_completed = payload.get("status").map(String::as_str) == Some("completed");
        // Unique swarm_id per sub-agent using tool_call_id
        let call_id = payload
            .get("id")
            .or_else(|| payload.get("tool_call_id"))
            .cloned()
            .unwrap_or_else(|| session_id.to_string());
        let unique_swarm_id = codex_make_swarm_id(&call_id);
        // Derive readable name from task
        let task_text = payload.get("task").cloned().unwrap_or_default();
        let readable = codex_readable_name(&task_text, &agent_label);
        let mut agent_payload = payload.clone();
        agent_payload.insert("agent_name".to_string(), agent_label);
        agent_payload.insert("readable_name".to_string(), readable.clone());
        agent_payload.insert("role".to_string(), role_name);
        agent_payload.insert(
            "title".to_string(),
            if is_completed {
                format!("{} — completed", readable)
            } else {
                readable
            },
        );
        agent_payload.insert("swarm_id".to_string(), unique_swarm_id.clone());
        agent_payload.insert("group_id".to_string(), format!("swarm-{}", unique_swarm_id));
        if !task_text.is_empty() {
            let text_preview = codex_truncate_str(&task_text, 500);
            agent_payload.insert("task_summary".to_string(), text_preview.clone());
            agent_payload.insert("text".to_string(), text_preview);
        }
        emit_raw(session_id, "agent", agent_payload);
    }

    if payload.get("status").map(String::as_str) != Some("completed") {
        return;
    }
    emit_synthetic_ide_event_if_needed(session_id, &tool, &payload);
}

fn emit_synthetic_ide_event_if_needed(
    session_id: &str,
    tool: &str,
    payload: &BTreeMap<String, String>,
) {
    let normalized = tool.strip_prefix("coderide_").unwrap_or(tool);
    let raw_type = match normalized {
        "todo_write"
        | "todo_read"
        | "plan_create"
        | "plan_read"
        | "plan_step_upsert"
        | "plan_step_batch_update"
        | "plan_step_reorder"
        | "plan_step_dependency_set"
        | "plan_set_walkthrough"
        | "plan_history_read"
        | "plan_diff"
        | "plan_request_user_input"
        | "debug_set_phase"
        | "debug_request_user"
        | "debug_resolve"
        | "policy_ack"
        | "activate_plan_mode"
        | "activate_debug_mode"
        | "show_task_panel"
        | "show_swarm_panel"
        | "mermaid_render" => normalized,
        _ => return,
    };
    emit_raw(session_id, raw_type, payload.clone());
}

fn emit_command_execution(session_id: &str, method: &str, item: &Value) {
    let mut payload = BTreeMap::new();
    if let Some(id) = item.get("id").and_then(string_value) {
        payload.insert("id".to_string(), id);
    }
    if let Some(command) = item.get("command").and_then(string_value) {
        payload.insert("command".to_string(), command);
    }
    if let Some(status) = item.get("status").and_then(string_value) {
        payload.insert("status".to_string(), normalize_status(&status));
    }
    // Extract command output/result — same pattern as emit_mcp_events.
    if let Some(result_text) = first_result_text(item.get("result")) {
        payload.insert("output".to_string(), result_text);
    } else if let Some(output) = item
        .get("output")
        .and_then(string_value)
        .or_else(|| item.get("stdout").and_then(string_value))
    {
        payload.insert("output".to_string(), output);
    }
    if method.ends_with("started") && !payload.contains_key("status") {
        payload.insert("status".to_string(), "started".to_string());
    }
    if method.ends_with("completed") && !payload.contains_key("status") {
        payload.insert("status".to_string(), "completed".to_string());
    }
    rust_codex_trace(format!(
        "emit command_execution method={} status={} command={}",
        method,
        payload.get("status").cloned().unwrap_or_default(),
        payload.get("command").cloned().unwrap_or_default()
    ));
    emit_raw(session_id, "command_execution", payload);
}

fn handle_server_request(
    stdin: &mut ChildStdin,
    value: &Value,
    method: &str,
) -> Result<(), String> {
    let id = json_rpc_id(value)?;
    match method {
        "item/tool/requestUserInput" => send_result(stdin, id, json!({ "answers": {} })),
        "item/tool/call" => send_result(
            stdin,
            id,
            json!({ "success": false, "contentItems": [{ "type": "inputText", "text": "SoloCode main chat does not expose dynamic tools on this transport." }] }),
        ),
        _ => send_error(stdin, id, -32601, format!("unsupported method: {method}")),
    }
}

fn thread_start_params(config: &MainChatProviderSessionConfig) -> Value {
    json!({
        "cwd": config.workspace_path,
        "model": config.codex_model_override.clone(),
        "modelProvider": config.codex_model_provider.clone(),
        "approvalPolicy": config.codex_ask_for_approval.clone().unwrap_or_else(|| "never".to_string()),
        "sandbox": sandbox_value(config),
        "baseInstructions": merged_codex_base_instructions(config.system_prompt.as_deref()),
        "developerInstructions": config.context_prompt.clone(),
        "ephemeral": true,
        "experimentalRawEvents": true,
        "persistExtendedHistory": true
    })
}

fn turn_input(config: &MainChatProviderSessionConfig) -> Vec<Value> {
    let mut items = vec![json!({"type": "text", "text": config.prompt, "text_elements": []})];
    for attachment in &config.attachments {
        if attachment.kind == "image" {
            items.push(json!({ "type": "localImage", "path": attachment.file_path }));
        }
    }
    items
}

fn sandbox_value(config: &MainChatProviderSessionConfig) -> &'static str {
    if config.codex_session_full_access {
        "danger-full-access"
    } else {
        match config.codex_sandbox.as_deref() {
            Some("read-only") | Some("workspace-read") => "read-only",
            Some("danger-full-access") => "danger-full-access",
            _ => "workspace-write",
        }
    }
}

fn read_json_line(reader: &mut BufReader<std::process::ChildStdout>) -> Result<Value, String> {
    let mut line = String::new();
    let bytes = reader
        .read_line(&mut line)
        .map_err(|error| format!("codex_app_server_read_failed:{error}"))?;
    if bytes == 0 {
        return Err("codex_app_server_eof".to_string());
    }
    serde_json::from_str(line.trim())
        .map_err(|error| format!("codex_app_server_decode_failed:{error}"))
}

fn handle_response_id<'a>(value: &'a Value, expected_id: i64) -> Result<Option<&'a Value>, String> {
    let Some(id_value) = value.get("id") else {
        return Ok(None);
    };
    if id_value.as_i64() != Some(expected_id) {
        return Ok(None);
    }
    if let Some(error) = value
        .get("error")
        .and_then(|item| item.get("message"))
        .and_then(string_value)
    {
        return Err(error);
    }
    Ok(value.get("result"))
}

/// Generates a stable, unique swarm_id from an ID string.
/// Internal only — never shown to the user.
fn codex_make_swarm_id(id: &str) -> String {
    let len = id.len();
    let suffix = if len > 12 { &id[len - 12..] } else { id };
    format!("sa-{}", suffix)
}

/// Truncates a string to max_chars, appending "…" if truncated.
fn codex_truncate_str(s: &str, max_chars: usize) -> String {
    if s.len() <= max_chars {
        return s.to_string();
    }
    let end = s.char_indices().nth(max_chars).map_or(s.len(), |(i, _)| i);
    format!("{}…", &s[..end])
}

/// Extracts role name from a Codex subagent tool name.
fn codex_subagent_role_name(tool: &str) -> String {
    let lower = tool.to_lowercase();
    if let Some(suffix) = lower
        .strip_prefix("coderide_subagent_")
        .or_else(|| lower.strip_prefix("subagent_"))
    {
        suffix.to_string()
    } else {
        "agent".to_string()
    }
}

/// Derives a readable display name from a task string for Codex sub-agents.
fn codex_readable_name(task: &str, fallback: &str) -> String {
    if task.is_empty() {
        return capitalize_first(fallback);
    }
    let filler_words: std::collections::HashSet<&str> = [
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "by",
        "for",
        "from",
        "i",
        "in",
        "into",
        "of",
        "on",
        "or",
        "the",
        "this",
        "to",
        "with",
        "analyze",
        "check",
        "explore",
        "find",
        "inspect",
        "investigate",
        "review",
        "search",
        "verify",
        "create",
        "implement",
        "write",
        "build",
        "code",
        "debug",
        "fix",
        "test",
        "document",
    ]
    .iter()
    .copied()
    .collect();

    let words: Vec<String> = task
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' {
                c
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .filter(|w| !filler_words.contains(&w.to_lowercase().as_str()) && w.len() > 1)
        .take(5)
        .map(|w| capitalize_first(w))
        .collect();

    if words.is_empty() {
        return capitalize_first(fallback);
    }
    let result = words.join(" ");
    if result.len() > 60 {
        result[..60].to_string()
    } else {
        result
    }
}

/// Capitalizes the first character of a string.
fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        capitalize_first, codex_make_swarm_id, codex_readable_name, codex_subagent_role_name,
        codex_truncate_str, is_operational_mcp_tool, ChildProcessGuard, CodexAgentMessageGate,
        CodexAgentMessagePhaseKind,
    };
    use serde_json::json;
    use std::process::Command;

    #[test]
    fn child_process_guard_kills_child_on_drop() {
        let child = Command::new("/bin/sh")
            .args(["-c", "sleep 5"])
            .spawn()
            .expect("spawn child");
        let pid = child.id();

        {
            let _guard = ChildProcessGuard::new(child);
        }

        let status = Command::new("/bin/sh")
            .args(["-c", &format!("kill -0 {pid} >/dev/null 2>&1")])
            .status()
            .expect("check child liveness");
        assert!(!status.success(), "child should be gone after guard drop");
    }

    #[test]
    fn codex_agent_message_gate_streams_text_immediately() {
        let mut gate = CodexAgentMessageGate::default();

        let (k0, _) = gate
            .push_agent_message_delta("Prima risposta. ", None)
            .unwrap();
        assert_eq!(k0, CodexAgentMessagePhaseKind::FinalAnswer);
        let (k1, _) = gate
            .push_agent_message_delta("Ancora testo.", None)
            .unwrap();
        assert_eq!(k1, CodexAgentMessagePhaseKind::FinalAnswer);
        assert_eq!(gate.cumulative_text(), "Prima risposta. Ancora testo.");
        assert_eq!(gate.release_after_operational_event(), None);
        let (k2, _) = gate
            .push_agent_message_delta(" Dopo il tool.", None)
            .unwrap();
        assert_eq!(k2, CodexAgentMessagePhaseKind::FinalAnswer);
        assert_eq!(
            gate.cumulative_text(),
            "Prima risposta. Ancora testo. Dopo il tool."
        );
    }

    #[test]
    fn codex_agent_message_gate_resolves_phase_from_item_started_map() {
        let mut gate = CodexAgentMessageGate::default();
        gate.record_agent_message_item_started("item_am_1".to_string(), "commentary".to_string());
        let payload = json!({"itemId": "item_am_1", "delta": "piano"});
        assert_eq!(
            gate.resolve_agent_message_phase_for_delta_payload(&payload)
                .as_deref(),
            Some("commentary")
        );
        let ph = gate.resolve_agent_message_phase_for_delta_payload(&payload);
        let (kind, visible) = gate
            .push_agent_message_delta("piano", ph.as_deref())
            .expect("commentary should remain visible");
        assert_eq!(kind, CodexAgentMessagePhaseKind::Commentary);
        assert_eq!(visible, "piano");
        assert_eq!(gate.cumulative_text(), "piano");
    }

    #[test]
    fn codex_agent_message_gate_keeps_commentary_and_final_answer_in_timeline() {
        let mut gate = CodexAgentMessageGate::default();
        let (k0, _) = gate
            .push_agent_message_delta("Usero skill. ", Some("commentary"))
            .expect("commentary should stay visible");
        assert_eq!(k0, CodexAgentMessagePhaseKind::Commentary);
        assert_eq!(gate.cumulative_text(), "Usero skill. ");

        let (k1, _) = gate
            .push_agent_message_delta("Ecco la risposta.", Some("final_answer"))
            .unwrap();
        assert_eq!(k1, CodexAgentMessagePhaseKind::FinalAnswer);
        assert_eq!(gate.cumulative_text(), "Usero skill. Ecco la risposta.");
    }

    #[test]
    fn codex_agent_message_gate_has_no_pending_flush_when_streaming_live() {
        let mut gate = CodexAgentMessageGate::default();
        assert!(gate
            .push_agent_message_delta("Risposta finale", None)
            .is_some());
        assert_eq!(gate.flush_pending(), None);
    }

    #[test]
    fn policy_ack_is_not_treated_as_operational_tool() {
        assert!(!is_operational_mcp_tool("coderide_policy_ack"));
        assert!(is_operational_mcp_tool("coderide_read"));
        assert!(is_operational_mcp_tool("coderide_todo_write"));
    }

    // -- codex_make_swarm_id --

    #[test]
    fn codex_make_swarm_id_uses_last_12_chars() {
        let sid = codex_make_swarm_id("item_01AbCdEfGhIjKlMn");
        // 22 chars total, last 12 = "CdEfGhIjKlMn"
        assert_eq!(sid, "sa-CdEfGhIjKlMn");
    }

    #[test]
    fn codex_make_swarm_id_short_id_intact() {
        assert_eq!(codex_make_swarm_id("short"), "sa-short");
    }

    #[test]
    fn codex_make_swarm_id_deterministic() {
        let id = "thread_abc123def456";
        assert_eq!(codex_make_swarm_id(id), codex_make_swarm_id(id));
    }

    #[test]
    fn codex_make_swarm_id_unique_for_different_ids() {
        assert_ne!(
            codex_make_swarm_id("thread_AAAAAAAAAAAA"),
            codex_make_swarm_id("thread_BBBBBBBBBBBB")
        );
    }

    // -- codex_subagent_role_name --

    #[test]
    fn codex_role_name_extracts_from_coderide_prefix() {
        assert_eq!(
            codex_subagent_role_name("coderide_subagent_explorer"),
            "explorer"
        );
        assert_eq!(codex_subagent_role_name("subagent_coder"), "coder");
    }

    #[test]
    fn codex_role_name_fallback_for_unknown() {
        assert_eq!(codex_subagent_role_name("read"), "agent");
    }

    // -- codex_readable_name --

    #[test]
    fn codex_readable_name_extracts_words() {
        let name = codex_readable_name("Analyze the database connection pooling", "Explorer");
        assert!(!name.is_empty());
        assert!(name.contains(' '), "Should have spaces: {}", name);
    }

    #[test]
    fn codex_readable_name_caps_at_5_words() {
        let name = codex_readable_name("one two three four five six seven eight", "Fallback");
        assert!(name.split_whitespace().count() <= 5);
    }

    #[test]
    fn codex_readable_name_empty_task_uses_fallback() {
        assert_eq!(codex_readable_name("", "Coder"), "Coder");
    }

    #[test]
    fn codex_readable_name_max_60_chars() {
        let long = "Longword ".repeat(20);
        let name = codex_readable_name(&long, "X");
        assert!(name.len() <= 60, "Too long: {}", name.len());
    }

    // -- capitalize_first --

    #[test]
    fn capitalize_first_works() {
        assert_eq!(capitalize_first("explorer"), "Explorer");
        assert_eq!(capitalize_first(""), "");
        assert_eq!(capitalize_first("A"), "A");
    }

    // -- codex_truncate_str --

    #[test]
    fn codex_truncate_short_unchanged() {
        assert_eq!(codex_truncate_str("ciao", 10), "ciao");
    }

    #[test]
    fn codex_truncate_long_truncated() {
        let long = "a".repeat(600);
        let result = codex_truncate_str(&long, 500);
        assert!(result.ends_with('…'));
        assert!(result.len() <= 504);
    }
}
