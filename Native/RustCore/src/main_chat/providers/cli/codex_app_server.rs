use super::codex_app_server_support::{
    first_result_text, is_turn_completed, json_rpc_id, normalize_status, raw_string_field,
    send_error, send_notification, send_request, send_result, spawn_stderr_collector,
};
use crate::main_chat::providers::common::string_value;
use crate::main_chat::providers::session::{emit_error, emit_raw, emit_text_delta, is_cancelled};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use serde_json::{json, Value};
use std::collections::BTreeMap;
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
        eprintln!("[RustCodexTrace] {}", message.as_ref());
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
    cumulative_text: String,
}

impl CodexAgentMessageGate {
    fn push_delta(&mut self, delta: &str) -> Option<String> {
        self.cumulative_text.push_str(delta);
        Some(delta.to_string())
    }

    fn cumulative_text(&self) -> String {
        self.cumulative_text.clone()
    }

    fn release_after_operational_event(&mut self) -> Option<String> {
        None
    }

    fn flush_pending(&mut self) -> Option<String> {
        None
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

    send_request(
        &mut stdin,
        1,
        "initialize",
        json!({
            "clientInfo": { "name": "solocode", "version": "1.0" },
            "capabilities": { "experimentalApi": true }
        }),
    )?;
    send_notification(&mut stdin, "notifications/initialized", json!({}))?;
    send_request(&mut stdin, 2, "config/mcpServer/reload", Value::Null)?;

    let thread_id = wait_for_thread_start(session_id, config, &mut stdin, &mut reader)?;
    start_turn(session_id, config, &thread_id, &mut stdin, &mut reader)?;
    let result = stream_until_turn_completed(session_id, &mut stdin, &mut reader);
    if let Err(error) = result {
        let tail = stderr_tail
            .lock()
            .ok()
            .map(|items| items.join("\n"))
            .unwrap_or_default();
        if tail.trim().is_empty() {
            return Err(error);
        }
        return Err(format!("{error}\n{tail}"));
    }
    Ok(())
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
                rust_codex_trace(format!("agent delta chars={}", delta.len()));
                if let Some(visible_delta) = gate.push_delta(&delta) {
                    rust_codex_trace(format!("emit text_delta chars={}", visible_delta.len()));
                    emit_text_delta(session_id, &visible_delta);
                    let cumulative = gate.cumulative_text();
                    let detail = cumulative
                        .split('\n')
                        .last()
                        .unwrap_or_default()
                        .chars()
                        .take(240)
                        .collect::<String>();
                    emit_raw(
                        session_id,
                        "assistant_update",
                        BTreeMap::from([
                            ("title".to_string(), "Working".to_string()),
                            ("detail".to_string(), detail),
                            ("output".to_string(), cumulative),
                            ("status".to_string(), "in_progress".to_string()),
                        ]),
                    );
                }
            }
        }
        "item/reasoning/textDelta" | "item/reasoning/summaryTextDelta" => {
            if let Some(delta) = raw_string_field(&payload, "delta") {
                rust_codex_trace(format!("reasoning delta chars={}", delta.len()));
                emit_raw(
                    session_id,
                    "reasoning",
                    BTreeMap::from([
                        ("output".to_string(), delta),
                        ("title".to_string(), "Reasoning".to_string()),
                    ]),
                );
            }
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
    let swarm_id = format!("swarm-codex-{}", session_id);

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

    let status = if is_completed { "completed" } else { "running" };
    let title = if is_completed {
        format!(
            "Sub Agent {} — {}",
            agent_label,
            if agent_status.is_empty() {
                "completed"
            } else {
                &agent_status
            }
        )
    } else {
        format!("Starting Sub Agent: {}", agent_label)
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
    payload.insert("title".to_string(), title);
    payload.insert("swarm_id".to_string(), swarm_id.clone());
    payload.insert("group_id".to_string(), swarm_id);
    if !sender_thread.is_empty() {
        payload.insert("sender_thread_id".to_string(), sender_thread);
    }
    if !new_thread.is_empty() {
        payload.insert("thread_id".to_string(), new_thread);
    }
    if !prompt.is_empty() {
        let text_preview = if prompt.len() > 200 {
            let end = prompt
                .char_indices()
                .nth(200)
                .map_or(prompt.len(), |(i, _)| i);
            format!("{}…", &prompt[..end])
        } else {
            prompt
        };
        payload.insert("text".to_string(), text_preview.clone());
        payload.insert("description".to_string(), text_preview);
    }

    eprintln!(
        "[CODEX_DEBUG] collabToolCall: method={} status={} agent={}",
        method,
        status,
        payload.get("agent_name").cloned().unwrap_or_default()
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
        let agent_label = tool
            .strip_prefix("coderide_subagent_")
            .unwrap_or(&tool)
            .to_string();
        let is_completed = payload.get("status").map(String::as_str) == Some("completed");
        let swarm_id = format!("swarm-codex-{}", session_id);
        let mut agent_payload = payload.clone();
        agent_payload.insert("agent_name".to_string(), agent_label.clone());
        agent_payload.insert(
            "title".to_string(),
            if is_completed {
                format!("Sub Agent {} — completed", agent_label)
            } else {
                format!("Starting Sub Agent: {}", agent_label)
            },
        );
        agent_payload.insert("swarm_id".to_string(), swarm_id.clone());
        agent_payload.insert("group_id".to_string(), swarm_id);
        if let Some(task) = agent_payload.get("task").cloned() {
            let text_preview = if task.len() > 200 {
                let end = task.char_indices().nth(200).map_or(task.len(), |(i, _)| i);
                format!("{}…", &task[..end])
            } else {
                task
            };
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
        "baseInstructions": config.system_prompt.clone(),
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

#[cfg(test)]
mod tests {
    use super::{is_operational_mcp_tool, ChildProcessGuard, CodexAgentMessageGate};
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

        assert_eq!(
            gate.push_delta("Prima risposta. ").as_deref(),
            Some("Prima risposta. ")
        );
        assert_eq!(
            gate.push_delta("Ancora testo.").as_deref(),
            Some("Ancora testo.")
        );
        assert_eq!(gate.cumulative_text(), "Prima risposta. Ancora testo.");
        assert_eq!(gate.release_after_operational_event(), None);
        assert_eq!(
            gate.push_delta(" Dopo il tool.").as_deref(),
            Some(" Dopo il tool.")
        );
        assert_eq!(
            gate.cumulative_text(),
            "Prima risposta. Ancora testo. Dopo il tool."
        );
    }

    #[test]
    fn codex_agent_message_gate_has_no_pending_flush_when_streaming_live() {
        let mut gate = CodexAgentMessageGate::default();
        assert_eq!(
            gate.push_delta("Risposta finale").as_deref(),
            Some("Risposta finale")
        );
        assert_eq!(gate.flush_pending(), None);
    }

    #[test]
    fn policy_ack_is_not_treated_as_operational_tool() {
        assert!(!is_operational_mcp_tool("coderide_policy_ack"));
        assert!(is_operational_mcp_tool("coderide_read"));
        assert!(is_operational_mcp_tool("coderide_todo_write"));
    }
}
