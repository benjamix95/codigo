use super::process::stream_process_lines;
use crate::main_chat::providers::common::{flatten_string_map, join_cli_prompt, string_value};
use crate::main_chat::providers::parsing::jsonl::parse_jsonl_line;
use crate::main_chat::providers::session::{
    emit_error, emit_raw, emit_text_delta, failover_to_next_cli_account, is_cancelled, running_cli_account,
};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use std::collections::BTreeMap;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let account = running_cli_account(session_id, config, "claude")?;
    let executable = account
        .as_ref()
        .and_then(|item| item.env_overrides.get("CLAUDE_PATH").cloned())
        .or_else(|| config.claude_path.clone())
        .ok_or_else(|| "missing_claude_path".to_string())?;
    let prompt = join_cli_prompt(
        config.system_prompt.as_deref(),
        &config.prompt,
        config.context_prompt.as_deref(),
        &config.attachments,
    );
    let mut args = vec![
        "-p".to_string(),
        prompt,
        "--output-format".to_string(),
        "stream-json".to_string(),
        "--verbose".to_string(),
    ];
    if let Some(model) = config.claude_model.clone().filter(|value| !value.trim().is_empty()) {
        args.extend(["--model".to_string(), model]);
    }
    if !config.claude_allowed_tools.is_empty() {
        args.extend([
            "--allowedTools".to_string(),
            config.claude_allowed_tools.join(","),
        ]);
    }
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if let Some(account) = account {
        environment.extend(account.env_overrides);
    }
    stream_process_lines(
        &executable,
        &args,
        &config.workspace_path,
        &environment,
        |line| consume_line(session_id, line),
        || is_cancelled(session_id),
    )
}

fn consume_line(session_id: &str, line: &str) -> Result<(), String> {
    let payloads = parse_jsonl_line(line);
    for json in payloads {
        if let Some(usage) = json.get("usage").and_then(|value| value.as_object()) {
            let mut payload = BTreeMap::new();
            if let Some(value) = usage
                .get("input_tokens")
                .or_else(|| usage.get("prompt_tokens"))
                .and_then(string_value)
            {
                payload.insert("input_tokens".to_string(), value);
            }
            if let Some(value) = usage
                .get("output_tokens")
                .or_else(|| usage.get("completion_tokens"))
                .and_then(string_value)
            {
                payload.insert("output_tokens".to_string(), value);
            }
            payload.insert("model".to_string(), "claude-cli".to_string());
            if payload.contains_key("input_tokens") && payload.contains_key("output_tokens") {
                emit_raw(session_id, "usage", payload);
            }
        }
        if let Some(event_type) = string_value(&json["type"]) {
            if event_type == "result" {
                if let Some(result) = string_value(&json["result"]) {
                    emit_text_delta(session_id, &result);
                }
                continue;
            }
            if event_type == "stream_event" {
                if let Some(delta) = json
                    .get("event")
                    .and_then(|value| value.get("delta"))
                    .and_then(|value| value.as_object())
                {
                    if delta.get("type").and_then(string_value) == Some("thinking_delta".to_string()) {
                        if let Some(thinking) = delta.get("thinking").and_then(string_value) {
                            emit_raw(
                                session_id,
                                "reasoning",
                                BTreeMap::from([
                                    ("output".to_string(), thinking),
                                    ("title".to_string(), "Reasoning".to_string()),
                                    ("group_id".to_string(), "reasoning-stream".to_string()),
                                ]),
                            );
                        }
                    }
                    if delta.get("type").and_then(string_value) == Some("text_delta".to_string()) {
                        if let Some(text) = delta.get("text").and_then(string_value) {
                            emit_text_delta(session_id, &text);
                        }
                    }
                }
                continue;
            }
        }
        if let Some(content) = json
            .get("message")
            .and_then(|value| value.get("content"))
            .and_then(|value| value.as_array())
        {
            for block in content {
                if block.get("type").and_then(string_value) == Some("text".to_string()) {
                    if let Some(text) = block.get("text").and_then(string_value) {
                        emit_text_delta(session_id, &text);
                    }
                }
                if block.get("type").and_then(string_value) == Some("thinking".to_string()) {
                    if let Some(thinking) = block
                        .get("thinking")
                        .and_then(string_value)
                        .or_else(|| block.get("text").and_then(string_value))
                    {
                        emit_raw(
                            session_id,
                            "reasoning",
                            BTreeMap::from([
                                ("output".to_string(), thinking),
                                ("title".to_string(), "Reasoning".to_string()),
                                ("group_id".to_string(), "reasoning-stream".to_string()),
                            ]),
                        );
                    }
                }
                if block.get("type").and_then(string_value) == Some("tool_use".to_string()) {
                    let name = block.get("name").and_then(string_value).unwrap_or_default();
                    emit_raw(session_id, &normalize_tool_name(&name), flatten_string_map(block));
                }
            }
        }
        if let Some(error) = json
            .get("error")
            .and_then(|v| v.as_str())
            .or_else(|| {
                json.get("message")
                    .and_then(|v| v.as_str())
            })
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
        {
            if error.to_lowercase().contains("rate limit") || error.to_lowercase().contains("quota") {
                if failover_to_next_cli_account(session_id, "claude", &error)? {
                    return Err("retry_with_next_account".to_string());
                }
            }
            emit_error(session_id, &error);
            return Err(error);
        }
    }
    Ok(())
}

fn normalize_tool_name(name: &str) -> String {
    let lowered = name.trim().to_lowercase();
    match lowered.as_str() {
        "mermaidrender" => "mermaid_render".to_string(),
        "planrequestuserinput" => "plan_request_user_input".to_string(),
        other => other.replace('-', "_"),
    }
}
