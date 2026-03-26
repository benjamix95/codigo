use super::process::stream_process_lines;
use crate::main_chat::providers::common::{
    apply_gui_safe_cli_path, flatten_string_map, join_cli_prompt, string_value,
};
use crate::main_chat::providers::parsing::jsonl::parse_jsonl_line;
use crate::main_chat::providers::session::{
    emit_error, emit_raw, emit_text_delta, failover_to_next_cli_account, is_cancelled,
    running_cli_account,
};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use std::collections::BTreeMap;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let account = running_cli_account(session_id, config, "gemini")?;
    let executable = account
        .as_ref()
        .and_then(|item| item.env_overrides.get("GEMINI_CLI_PATH").cloned())
        .or_else(|| config.gemini_cli_path.clone())
        .ok_or_else(|| "missing_gemini_path".to_string())?;
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
        "json".to_string(),
    ];
    if let Some(model) = config
        .gemini_model_override
        .clone()
        .filter(|value| !value.trim().is_empty())
    {
        args.splice(0..0, ["-m".to_string(), model]);
    }
    let mut environment = std::env::vars().collect::<BTreeMap<_, _>>();
    if let Some(account) = account {
        environment.extend(account.env_overrides);
    }
    apply_gui_safe_cli_path(&mut environment);
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
    if payloads.is_empty() {
        if !line.trim().is_empty() {
            emit_text_delta(session_id, line);
            emit_text_delta(session_id, "\n");
        }
        return Ok(());
    }
    for json in payloads {
        if let Some(raw_event) = parse_raw_event(&json) {
            emit_raw(session_id, &raw_event.0, raw_event.1);
        }
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
            payload.insert("model".to_string(), "gemini-cli".to_string());
            if payload.contains_key("input_tokens") && payload.contains_key("output_tokens") {
                emit_raw(session_id, "usage", payload);
            }
        }
        if let Some(text) = extract_text(&json) {
            emit_text_delta(session_id, &text);
        }
        if let Some(error) = json
            .get("error")
            .and_then(string_value)
            .or_else(|| json.get("message").and_then(string_value))
        {
            if error.to_lowercase().contains("rate limit") || error.to_lowercase().contains("quota")
            {
                if failover_to_next_cli_account(session_id, "gemini", &error)? {
                    return Err("retry_with_next_account".to_string());
                }
            }
            emit_error(session_id, &error);
            return Err(error);
        }
    }
    Ok(())
}

fn parse_raw_event(json: &serde_json::Value) -> Option<(String, BTreeMap<String, String>)> {
    let item = json.get("item").unwrap_or(json);
    let item_type = item
        .get("type")
        .and_then(string_value)
        .or_else(|| item.get("event_type").and_then(string_value))
        .unwrap_or_default()
        .to_lowercase();
    if item_type == "reasoning" || item_type == "thinking" {
        let output = extract_text(item)?;
        return Some((
            "reasoning".to_string(),
            BTreeMap::from([
                ("output".to_string(), output),
                ("title".to_string(), "Reasoning".to_string()),
                ("group_id".to_string(), "reasoning-stream".to_string()),
            ]),
        ));
    }
    let tool_name = item
        .get("tool")
        .and_then(string_value)
        .or_else(|| item.get("name").and_then(string_value));
    tool_name.map(|tool_name| {
        (
            tool_name.replace('-', "_").to_lowercase(),
            flatten_string_map(item),
        )
    })
}

fn extract_text(value: &serde_json::Value) -> Option<String> {
    if let Some(text) = value.get("response").and_then(string_value) {
        return Some(text);
    }
    if let Some(text) = value.get("result").and_then(string_value) {
        return Some(text);
    }
    if let Some(text) = value.get("output").and_then(string_value) {
        return Some(text);
    }
    if let Some(text) = value.get("text").and_then(string_value) {
        return Some(text);
    }
    None
}
