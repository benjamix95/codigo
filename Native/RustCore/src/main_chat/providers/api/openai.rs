use crate::main_chat::providers::common::{api_user_prompt, image_data_urls, string_value};
use crate::main_chat::providers::parsing::sse::sse_data_payload;
use crate::main_chat::providers::session::{emit_error, emit_raw, emit_text_delta, is_cancelled};
use app_core_protocol::main_chat_provider::MainChatProviderSessionConfig;
use reqwest::blocking::Client;
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader};
use std::time::Duration;

pub(crate) fn run(session_id: &str, config: &MainChatProviderSessionConfig) -> Result<(), String> {
    let api_key = config.api_key.clone().unwrap_or_default();
    if api_key.trim().is_empty() {
        return Err("missing_openai_api_key".to_string());
    }
    let url = config
        .base_url
        .clone()
        .unwrap_or_else(|| "https://api.openai.com/v1/chat/completions".to_string());
    let model = config
        .model
        .clone()
        .unwrap_or_else(|| "gpt-4o-mini".to_string());
    let system_prompt = config
        .system_prompt
        .clone()
        .unwrap_or_else(|| "You are Codex.".to_string());
    let user_prompt = api_user_prompt(&config.prompt, config.context_prompt.as_deref());
    let client = Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
        .map_err(|error| format!("openai_client_build_failed:{error}"))?;

    let user_content = if image_data_urls(&config.attachments).is_empty() {
        Value::String(user_prompt)
    } else {
        let mut items = vec![json!({"type":"text","text":user_prompt})];
        for item in image_data_urls(&config.attachments) {
            items.push(json!({"type":"image_url","image_url":{"url": item["url"].clone()}}));
        }
        Value::Array(items)
    };
    let mut body = json!({
        "model": model,
        "messages": [
            {"role":"system","content":system_prompt},
            {"role":"user","content":user_content}
        ],
        "stream": true
    });
    if let Some(tools_json) = config.tool_definitions_json.as_deref() {
        if let Ok(tools) = serde_json::from_str::<Value>(tools_json) {
            body["tools"] = tools;
            body["tool_choice"] = Value::String("auto".to_string());
            body["stream_options"] = json!({"include_usage": true});
        }
    }
    let mut request = client
        .post(url)
        .header(AUTHORIZATION, format!("Bearer {api_key}"))
        .header(CONTENT_TYPE, "application/json")
        .header(ACCEPT, "text/event-stream");
    for (key, value) in &config.extra_headers {
        request = request.header(key, value);
    }
    let response = request
        .json(&body)
        .send()
        .map_err(|error| format!("openai_request_failed:{error}"))?;
    if !response.status().is_success() {
        return Err(format!("openai_http_{}", response.status().as_u16()));
    }
    let reader = BufReader::new(response);
    for line in reader.lines() {
        if is_cancelled(session_id) {
            return Err("cancelled".to_string());
        }
        let payload = line.map_err(|error| format!("openai_stream_read_failed:{error}"))?;
        let Some(payload) = sse_data_payload(&payload) else {
            continue;
        };
        if payload == "[DONE]" {
            return Ok(());
        }
        let json = serde_json::from_str::<Value>(payload)
            .map_err(|error| format!("openai_payload_decode_failed:{error}"))?;
        consume_payload(session_id, &json);
    }
    Ok(())
}

fn consume_payload(session_id: &str, json: &Value) {
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
        payload.insert("model".to_string(), "openai-api".to_string());
        emit_raw(session_id, "usage", payload);
    }
    if let Some(error) = json
        .get("error")
        .and_then(|value| value.get("message"))
        .and_then(string_value)
    {
        emit_error(session_id, &error);
        return;
    }
    let Some(choice) = json
        .get("choices")
        .and_then(|value| value.as_array())
        .and_then(|value| value.first())
    else {
        return;
    };
    if let Some(delta) = choice.get("delta") {
        if let Some(reasoning) = delta.get("reasoning_content").and_then(string_value) {
            emit_raw(
                session_id,
                "reasoning",
                BTreeMap::from([
                    ("output".to_string(), reasoning),
                    ("title".to_string(), "Reasoning".to_string()),
                    ("group_id".to_string(), "reasoning-stream".to_string()),
                ]),
            );
        }
        if let Some(text) = delta.get("content").and_then(string_value) {
            emit_text_delta(session_id, &text);
        }
        if let Some(tool_calls) = delta.get("tool_calls").and_then(|value| value.as_array()) {
            for tool_call in tool_calls {
                let mut payload = BTreeMap::new();
                if let Some(value) = tool_call.get("id").and_then(string_value) {
                    payload.insert("id".to_string(), value);
                }
                if let Some(value) = tool_call
                    .get("function")
                    .and_then(|value| value.get("name"))
                    .and_then(string_value)
                {
                    payload.insert("name".to_string(), value);
                }
                if let Some(value) = tool_call
                    .get("function")
                    .and_then(|value| value.get("arguments"))
                    .and_then(string_value)
                {
                    payload.insert("args".to_string(), value);
                }
                payload.insert("is_partial".to_string(), "true".to_string());
                emit_raw(session_id, "tool_call_suggested", payload);
            }
        }
    }
}
