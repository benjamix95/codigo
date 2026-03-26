use super::process::stream_process_lines;
use crate::main_chat::providers::common::{join_cli_prompt, string_value};
use crate::main_chat::providers::session::{emit_error, emit_raw, emit_text_delta, is_cancelled};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let executable = config
        .kilo_path
        .as_ref()
        .filter(|path| !path.trim().is_empty())
        .ok_or_else(|| "missing_kilo_path".to_string())?;
    if !Path::new(executable).exists() {
        return Err(format!(
            "kilo_cli_not_found:{executable}. Install with: npm i -g kilo-code"
        ));
    }

    let prompt = join_cli_prompt(
        config.system_prompt.as_deref(),
        &config.prompt,
        config.context_prompt.as_deref(),
        &config.attachments,
    );

    let mut args = vec![
        "run".to_string(),
        "--format".to_string(),
        "json".to_string(),
        "--auto".to_string(),
    ];
    let model = config
        .model
        .as_ref()
        .or(config.kilo_model.as_ref())
        .and_then(|value| {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        });
    if let Some(model) = model {
        args.push("-m".to_string());
        args.push(model);
    }
    args.push("--dir".to_string());
    args.push(config.workspace_path.clone());
    for attachment in &config.attachments {
        if attachment.kind == "image" && !attachment.file_path.trim().is_empty() {
            args.push("-f".to_string());
            args.push(attachment.file_path.clone());
        }
    }
    args.push(prompt);

    let environment = std::env::vars().collect::<BTreeMap<_, _>>();
    stream_process_lines(
        executable,
        &args,
        &config.workspace_path,
        &environment,
        |line| consume_line(session_id, line, config),
        || is_cancelled(session_id),
    )
}

fn consume_line(
    session_id: &str,
    line: &str,
    config: &MainChatProviderSessionConfig,
) -> Result<(), String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return Ok(());
    }
    let json: Value = match serde_json::from_str(trimmed) {
        Ok(value) => value,
        Err(_) => {
            emit_text_delta(session_id, trimmed);
            emit_text_delta(session_id, "\n");
            return Ok(());
        }
    };

    let event_type = json
        .get("type")
        .and_then(string_value)
        .unwrap_or_default()
        .to_lowercase();

    match event_type.as_str() {
        "text" => {
            if let Some(part) = json.get("part").and_then(|value| value.as_object()) {
                if let Some(text) = part.get("text").and_then(string_value) {
                    if !text.is_empty() {
                        emit_text_delta(session_id, &text);
                    }
                }
            }
        }
        "tool_start" => {
            if let Some(part) = json.get("part") {
                let (tool_type, payload) = tool_start_mapping(part);
                emit_raw(session_id, &tool_type, payload);
            }
        }
        "tool_finish" => {
            if let Some(part) = json.get("part").and_then(|value| value.as_object()) {
                let output = part
                    .get("output")
                    .or_else(|| part.get("result"))
                    .or_else(|| part.get("text"))
                    .and_then(string_value)
                    .unwrap_or_default();
                if !output.is_empty() {
                    let name = part
                        .get("name")
                        .and_then(string_value)
                        .unwrap_or_else(|| "tool".to_string());
                    let clipped: String = output.chars().take(4_000).collect();
                    let mut payload = BTreeMap::new();
                    payload.insert("title".to_string(), name.clone());
                    payload.insert("output".to_string(), clipped);
                    payload.insert("tool".to_string(), name.clone());
                    payload.insert("status".to_string(), "completed".to_string());
                    emit_raw(session_id, "command_execution", payload);
                }
            }
        }
        "step_start" => {
            if let Some(part) = json.get("part") {
                emit_step_start_reasoning(session_id, part);
            }
        }
        "step_finish" => {
            if let Some(part) = json.get("part").and_then(|value| value.as_object()) {
                if let Some(tokens) = part.get("tokens").and_then(|value| value.as_object()) {
                    let input = int_from_json(tokens.get("input")).unwrap_or(0);
                    let output = int_from_json(tokens.get("output")).unwrap_or(0);
                    if input > 0 || output > 0 {
                        let model_label = config
                            .model
                            .as_deref()
                            .or(config.kilo_model.as_deref())
                            .filter(|value| !value.trim().is_empty())
                            .unwrap_or("kilo");
                        let mut payload = BTreeMap::new();
                        payload.insert("input_tokens".to_string(), input.to_string());
                        payload.insert("output_tokens".to_string(), output.to_string());
                        payload.insert("model".to_string(), model_label.to_string());
                        emit_raw(session_id, "usage", payload);
                    }
                }
            }
        }
        "error" => {
            let message = json
                .get("message")
                .or_else(|| json.get("error"))
                .and_then(string_value)
                .unwrap_or_else(|| "Unknown Kilo error".to_string());
            emit_error(session_id, &message);
            return Err(message);
        }
        _ => {}
    }
    Ok(())
}

fn tool_start_mapping(part: &Value) -> (String, BTreeMap<String, String>) {
    let name = part
        .get("name")
        .and_then(string_value)
        .unwrap_or_else(|| "tool".to_string());
    let tool_type = name.replace('-', "_").to_lowercase();
    (tool_type, merge_tool_inputs(part))
}

fn merge_tool_inputs(part: &Value) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    if let Some(input) = part.get("input") {
        if let Some(object) = input.as_object() {
            for (key, value) in object {
                if let Some(text) = string_value(value) {
                    map.insert(key.clone(), text);
                }
            }
        } else if let Some(text) = string_value(input) {
            map.insert("detail".to_string(), text);
        }
    }
    if let Some(args) = part.get("args") {
        if let Some(object) = args.as_object() {
            for (key, value) in object {
                if map.contains_key(key) {
                    continue;
                }
                if let Some(text) = string_value(value) {
                    map.insert(key.clone(), text);
                }
            }
        } else if !map.contains_key("detail") {
            if let Some(text) = string_value(args) {
                map.insert("detail".to_string(), text);
            }
        }
    }
    map
}

fn emit_step_start_reasoning(session_id: &str, part: &Value) {
    if let Some(kind) = part.get("kind").and_then(string_value) {
        let normalized = kind.to_lowercase();
        if normalized == "reasoning" || normalized == "thinking" {
            if let Some(text) = part
                .get("text")
                .and_then(string_value)
                .or_else(|| part.get("content").and_then(string_value))
            {
                emit_reasoning_chunk(session_id, &text);
            }
        }
    }
    if let Some(text) = part.get("thinking").and_then(string_value) {
        emit_reasoning_chunk(session_id, &text);
    }
    if let Some(text) = part.get("reasoning").and_then(string_value) {
        emit_reasoning_chunk(session_id, &text);
    }
}

fn emit_reasoning_chunk(session_id: &str, text: &str) {
    emit_raw(
        session_id,
        "reasoning",
        BTreeMap::from([
            ("output".to_string(), text.to_string()),
            ("title".to_string(), "Reasoning".to_string()),
            ("group_id".to_string(), "reasoning-stream".to_string()),
        ]),
    );
}

fn int_from_json(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(number) => number.as_i64().or_else(|| number.as_f64().map(|f| f as i64)),
        Value::String(text) => text.trim().parse().ok(),
        _ => None,
    }
}
