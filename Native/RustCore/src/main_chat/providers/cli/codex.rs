use super::codex_app_server;
use crate::main_chat::providers::common::{
    apply_gui_safe_cli_path, flatten_string_map, string_value,
};
use crate::main_chat::providers::parsing::jsonl::parse_jsonl_line;
use crate::main_chat::providers::session::{
    emit_error, emit_raw, emit_text_delta, failover_to_next_cli_account, running_cli_account,
};
use app_core_protocol::main_chat_provider::{
    MainChatCLIAccountSnapshot, MainChatProviderSessionConfig,
};
use std::collections::BTreeMap;
use std::path::Path;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let account = running_cli_account(session_id, config, "codex")?;
    let executable = resolve_codex_executable(account.as_ref(), config)?;
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if let Some(account) = account {
        environment.extend(account.env_overrides);
    }
    apply_gui_safe_cli_path(&mut environment);
    codex_app_server::run(session_id, config, &executable, &environment)
}

fn resolve_codex_executable(
    account: Option<&MainChatCLIAccountSnapshot>,
    config: &MainChatProviderSessionConfig,
) -> Result<String, String> {
    resolve_codex_executable_with(account, config, detect_codex_path)
}

fn resolve_codex_executable_with<F>(
    account: Option<&MainChatCLIAccountSnapshot>,
    config: &MainChatProviderSessionConfig,
    detect: F,
) -> Result<String, String>
where
    F: Fn() -> Option<String>,
{
    let candidates = [
        account.and_then(|item| item.env_overrides.get("CODEX_PATH").cloned()),
        config.codex_path.clone(),
        detect(),
    ];
    candidates
        .into_iter()
        .flatten()
        .find_map(valid_executable_path)
        .ok_or_else(|| "missing_codex_path".to_string())
}

fn valid_executable_path(candidate: String) -> Option<String> {
    let trimmed = candidate.trim();
    if trimmed.is_empty() {
        return None;
    }
    let path = Path::new(trimmed);
    if path.is_file() {
        return Some(trimmed.to_string());
    }
    None
}

fn detect_codex_path() -> Option<String> {
    find_in_path(std::env::var("PATH").ok().as_deref().unwrap_or(""), "codex").or_else(|| {
        default_codex_candidates()
            .into_iter()
            .find_map(valid_executable_path)
    })
}

fn find_in_path(path_env: &str, executable: &str) -> Option<String> {
    path_env
        .split(':')
        .filter(|segment| !segment.trim().is_empty())
        .map(|dir| format!("{dir}/{executable}"))
        .find_map(valid_executable_path)
}

fn default_codex_candidates() -> Vec<String> {
    let home = std::env::var("HOME").unwrap_or_default();
    [
        "/opt/homebrew/bin/codex".to_string(),
        "/usr/local/bin/codex".to_string(),
        format!("{home}/.npm/bin/codex"),
        format!("{home}/.local/bin/codex"),
        format!("{home}/.yarn/bin/codex"),
        format!("{home}/.bun/bin/codex"),
    ]
    .into_iter()
    .filter(|path| !path.contains("//"))
    .collect()
}

fn build_exec_arguments(config: &MainChatProviderSessionConfig, prompt: &str) -> Vec<String> {
    let mut args = vec!["exec".to_string()];
    let image_paths = config
        .attachments
        .iter()
        .filter(|attachment| attachment.kind == "image")
        .map(|attachment| attachment.file_path.clone())
        .collect::<Vec<_>>();
    if !image_paths.is_empty() {
        args.push("--image".to_string());
        args.push(image_paths.join(","));
    }
    args.push("--json".to_string());
    if !config.codex_session_full_access {
        args.push("--full-auto".to_string());
    }
    args.push("--sandbox".to_string());
    args.push(
        config
            .codex_sandbox
            .clone()
            .unwrap_or_else(|| "workspace-write".to_string()),
    );
    args.push("--cd".to_string());
    args.push(config.workspace_path.clone());
    insert_before_prompt(
        &mut args,
        flag_value("--model", config.codex_model_override.clone()),
    );
    insert_before_prompt(
        &mut args,
        flag_value(
            "-c",
            config
                .codex_reasoning_effort
                .clone()
                .map(|value| format!("model_reasoning_effort={value}")),
        ),
    );
    insert_before_prompt(
        &mut args,
        flag_value(
            "-c",
            config
                .codex_model_provider
                .clone()
                .map(|value| format!("model_provider=\"{value}\"")),
        ),
    );
    insert_before_prompt(
        &mut args,
        Some(vec![
            "-c".to_string(),
            format!(
                "fast_mode={}",
                if config.codex_fast_mode {
                    "true"
                } else {
                    "false"
                }
            ),
        ]),
    );
    insert_before_prompt(
        &mut args,
        Some(vec![
            "-c".to_string(),
            format!(
                "approval_policy=\"{}\"",
                config
                    .codex_ask_for_approval
                    .clone()
                    .unwrap_or_else(|| "never".to_string())
            ),
        ]),
    );
    args.push(prompt.to_string());
    args
}

fn insert_before_prompt(target: &mut Vec<String>, value: Option<Vec<String>>) {
    if let Some(value) = value {
        target.extend(value);
    }
}

fn flag_value(flag: &str, value: Option<String>) -> Option<Vec<String>> {
    value
        .filter(|value| !value.trim().is_empty())
        .map(|value| vec![flag.to_string(), value])
}

fn consume_line(session_id: &str, line: &str) -> Result<(), String> {
    let payloads = parse_jsonl_line(line);
    if payloads.is_empty() {
        if !line.trim().is_empty() {
            emit_text_delta(session_id, line);
            emit_text_delta(session_id, "\n");
        }
        return Ok(());
    }
    for json in payloads {
        if let Some(raw_type) = string_value(&json["type"]) {
            let lowered = raw_type.to_lowercase();
            if lowered == "turn.started" || lowered == "turn_started" {
                emit_raw(session_id, "turn_started", BTreeMap::new());
                continue;
            }
            if lowered == "turn.completed" || lowered == "turn_completed" {
                emit_raw(session_id, "turn_completed", BTreeMap::new());
            }
            if lowered.contains("reasoning") || lowered.contains("thinking") {
                let output = string_value(&json["text"])
                    .or_else(|| string_value(&json["output"]))
                    .or_else(|| string_value(&json["content"]))
                    .unwrap_or_default();
                if !output.is_empty() {
                    emit_raw(
                        session_id,
                        "reasoning",
                        BTreeMap::from([
                            ("output".to_string(), output),
                            ("title".to_string(), "Reasoning".to_string()),
                            ("group_id".to_string(), "reasoning-stream".to_string()),
                        ]),
                    );
                }
            }
            if lowered.starts_with("item.") {
                consume_item_event(session_id, &lowered, &json);
            }
        }
        if let Some(usage) = json.get("usage").and_then(|value| value.as_object()) {
            let mut payload = BTreeMap::new();
            if let Some(value) = usage.get("input_tokens").and_then(string_value) {
                payload.insert("input_tokens".to_string(), value);
            }
            if let Some(value) = usage
                .get("output_tokens")
                .or_else(|| usage.get("completion_tokens"))
                .and_then(string_value)
            {
                payload.insert("output_tokens".to_string(), value);
            }
            payload.insert("model".to_string(), "codex-cli".to_string());
            if payload.contains_key("input_tokens") && payload.contains_key("output_tokens") {
                emit_raw(session_id, "usage", payload);
            }
        }
        if let Some(content) = string_value(&json["content"]) {
            emit_text_delta(session_id, &content);
        }
        if let Some(delta) = string_value(&json["delta"]) {
            emit_text_delta(session_id, &delta);
        }
        if let Some(name) = string_value(&json["tool"]).or_else(|| string_value(&json["name"])) {
            let payload = flatten_string_map(&json);
            emit_raw(session_id, &normalize_tool_name(&name), payload);
        }
        if let Some(error) = json
            .get("error")
            .and_then(|v| v.as_str())
            .or_else(|| json.get("message").and_then(|v| v.as_str()))
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
        {
            if error.to_lowercase().contains("rate limit") || error.to_lowercase().contains("quota")
            {
                if failover_to_next_cli_account(session_id, "codex", &error)? {
                    return Err("retry_with_next_account".to_string());
                }
            }
            emit_error(session_id, &error);
            return Err(error);
        }
    }
    Ok(())
}

fn consume_item_event(session_id: &str, event_type: &str, json: &serde_json::Value) {
    let item = match json.get("item").and_then(|v| v.as_object()) {
        Some(obj) => obj,
        None => return,
    };
    let item_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
    let item_id = item.get("id").and_then(|v| v.as_str()).unwrap_or("");

    match item_type {
        "agent_message" => {
            if let Some(text) = item.get("text").and_then(|v| v.as_str()) {
                if !text.is_empty() {
                    emit_text_delta(session_id, text);
                }
            }
        }
        "reasoning" => {
            let output = item
                .get("text")
                .or_else(|| item.get("output"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            if !output.is_empty() {
                emit_raw(
                    session_id,
                    "reasoning",
                    BTreeMap::from([
                        ("output".to_string(), output.to_string()),
                        ("title".to_string(), "Reasoning".to_string()),
                        ("group_id".to_string(), "reasoning-stream".to_string()),
                    ]),
                );
            }
        }
        "command_execution" => {
            let mut payload = BTreeMap::new();
            if let Some(cmd) = item.get("command").and_then(|v| v.as_str()) {
                payload.insert("command".to_string(), cmd.to_string());
            }
            if let Some(status) = item.get("status").and_then(|v| v.as_str()) {
                payload.insert("status".to_string(), status.to_string());
            }
            if !item_id.is_empty() {
                payload.insert("id".to_string(), item_id.to_string());
            }
            let raw_name = if event_type.ends_with("completed") {
                "shell_completed"
            } else {
                "shell"
            };
            emit_raw(session_id, raw_name, payload);
        }
        other => {
            let mut payload = BTreeMap::new();
            payload.insert("item_type".to_string(), other.to_string());
            if !item_id.is_empty() {
                payload.insert("id".to_string(), item_id.to_string());
            }
            if let Some(status) = item.get("status").and_then(|v| v.as_str()) {
                payload.insert("status".to_string(), status.to_string());
            }
            let raw_name = if event_type.ends_with("completed") {
                &format!("{other}_completed")
            } else {
                other
            };
            emit_raw(session_id, raw_name, payload);
        }
    }
}

fn normalize_tool_name(name: &str) -> String {
    let lowered = name.trim().to_lowercase();
    match lowered.as_str() {
        "todo_write" | "todo-read" | "todo_read" => lowered.replace('-', "_"),
        "planrequestuserinput" => "plan_request_user_input".to_string(),
        "mermaidrender" => "mermaid_render".to_string(),
        other => other.to_string(),
    }
}

#[cfg(test)]
mod tests;
