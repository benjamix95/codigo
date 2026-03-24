use crate::main_chat::providers::common::{api_user_prompt, image_data_urls, string_value};
use crate::main_chat::providers::parsing::sse::sse_data_payload;
use crate::main_chat::providers::session::{emit_error, emit_raw, emit_text_delta, is_cancelled};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use reqwest::blocking::Client;
use reqwest::header::{ACCEPT, CONTENT_TYPE};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader};
use std::time::Duration;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let api_key = config.api_key.clone().unwrap_or_default();
    if api_key.trim().is_empty() {
        return Err("missing_anthropic_api_key".to_string());
    }
    let model = config
        .model
        .clone()
        .unwrap_or_else(|| "claude-sonnet-4-6".to_string());
    let system_prompt = config
        .system_prompt
        .clone()
        .unwrap_or_else(|| "You are Codex.".to_string());
    let user_prompt = api_user_prompt(&config.prompt, config.context_prompt.as_deref());
    let client = Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
        .map_err(|error| format!("anthropic_client_build_failed:{error}"))?;
    let content = if image_data_urls(&config.attachments).is_empty() {
        json!([{ "type": "text", "text": user_prompt }])
    } else {
        let mut items = vec![json!({"type":"text","text":user_prompt})];
        for item in image_data_urls(&config.attachments) {
            items.push(json!({
                "type":"image",
                "source":{"type":"base64","media_type":"image/jpeg","data": item["url"].split(',').last().unwrap_or_default()}
            }));
        }
        Value::Array(items)
    };
    let mut body = json!({
        "model": model,
        "max_tokens": 4096,
        "stream": true,
        "system": system_prompt,
        "messages": [{"role":"user","content": content}]
    });
    if let Some(tools_json) = config.tool_definitions_json.as_deref() {
        if let Ok(tools) = serde_json::from_str::<Value>(tools_json) {
            body["tools"] = tools;
        }
    }
    let response = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", api_key)
        .header("anthropic-version", "2023-06-01")
        .header(CONTENT_TYPE, "application/json")
        .header(ACCEPT, "text/event-stream")
        .json(&body)
        .send()
        .map_err(|error| format!("anthropic_request_failed:{error}"))?;
    if !response.status().is_success() {
        return Err(format!("anthropic_http_{}", response.status().as_u16()));
    }
    let reader = BufReader::new(response);
    for line in reader.lines() {
        if is_cancelled(session_id) {
            return Err("cancelled".to_string());
        }
        let payload = line.map_err(|error| format!("anthropic_stream_read_failed:{error}"))?;
        let Some(payload) = sse_data_payload(&payload) else {
            continue;
        };
        if payload == "[DONE]" {
            return Ok(());
        }
        let json = serde_json::from_str::<Value>(payload)
            .map_err(|error| format!("anthropic_payload_decode_failed:{error}"))?;
        consume_payload(session_id, &json);
    }
    Ok(())
}

fn consume_payload(session_id: &str, json: &Value) {
    let Some(event_type) = json.get("type").and_then(string_value) else {
        return;
    };
    match event_type.as_str() {
        "content_block_delta" => {
            let Some(delta) = json.get("delta") else {
                return;
            };
            let delta_type = delta.get("type").and_then(string_value).unwrap_or_default();
            if delta_type == "thinking_delta" {
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
            } else if delta_type == "text_delta" {
                if let Some(text) = delta.get("text").and_then(string_value) {
                    emit_text_delta(session_id, &text);
                }
            } else if delta_type == "input_json_delta" {
                emit_raw(
                    session_id,
                    "tool_call_suggested",
                    BTreeMap::from([
                        (
                            "args_fragment".to_string(),
                            delta
                                .get("partial_json")
                                .and_then(string_value)
                                .unwrap_or_default(),
                        ),
                        ("is_partial".to_string(), "true".to_string()),
                    ]),
                );
            }
        }
        "content_block_start" => {
            if let Some(block) = json.get("content_block") {
                if block.get("type").and_then(string_value) == Some("tool_use".to_string()) {
                    let mut payload = BTreeMap::new();
                    if let Some(value) = block.get("id").and_then(string_value) {
                        payload.insert("id".to_string(), value);
                    }
                    if let Some(value) = block.get("name").and_then(string_value) {
                        payload.insert("name".to_string(), value);
                    }
                    if let Some(value) = block
                        .get("input")
                        .and_then(|value| serde_json::to_string(value).ok())
                    {
                        payload.insert("args".to_string(), value);
                    }
                    payload.insert("is_partial".to_string(), "false".to_string());
                    emit_raw(session_id, "tool_call_suggested", payload);
                }
            }
        }
        "message_delta" => {
            if let Some(usage) = json.get("usage").and_then(|value| value.as_object()) {
                let mut payload = BTreeMap::new();
                if let Some(value) = usage.get("input_tokens").and_then(string_value) {
                    payload.insert("input_tokens".to_string(), value);
                }
                if let Some(value) = usage.get("output_tokens").and_then(string_value) {
                    payload.insert("output_tokens".to_string(), value);
                }
                payload.insert("model".to_string(), "anthropic-api".to_string());
                emit_raw(session_id, "usage", payload);
            }
        }
        "error" => {
            let message = json
                .get("error")
                .and_then(|value| value.get("message"))
                .and_then(string_value)
                .unwrap_or_else(|| "Anthropic API error".to_string());
            emit_error(session_id, &message);
        }
        _ => {}
    }
}
