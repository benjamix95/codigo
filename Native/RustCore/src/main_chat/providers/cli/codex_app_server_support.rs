use crate::main_chat::providers::common::string_value;
use app_core_protocol::jsonrpc::{JsonRpcErrorResponse, JsonRpcId, JsonRpcResponse};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::process::ChildStdin;
use std::sync::{Arc, Mutex};
use std::thread;

pub(super) fn send_request(
    stdin: &mut ChildStdin,
    id: i64,
    method: &str,
    params: Value,
) -> Result<(), String> {
    let payload = json!({"jsonrpc": "2.0", "id": id, "method": method, "params": if params.is_null() { Value::Object(Default::default()) } else { params }});
    write_json_line(stdin, &payload)
}

pub(super) fn send_notification(
    stdin: &mut ChildStdin,
    method: &str,
    params: Value,
) -> Result<(), String> {
    write_json_line(
        stdin,
        &json!({"jsonrpc": "2.0", "method": method, "params": params}),
    )
}

pub(super) fn send_result(
    stdin: &mut ChildStdin,
    id: JsonRpcId,
    result: Value,
) -> Result<(), String> {
    write_json_line(stdin, &JsonRpcResponse::ok(id, result))
}

pub(super) fn send_error(
    stdin: &mut ChildStdin,
    id: JsonRpcId,
    code: i64,
    message: String,
) -> Result<(), String> {
    let response = match code {
        -32601 => JsonRpcErrorResponse::method_not_found(id, message),
        _ => JsonRpcErrorResponse::invalid_request(id, message),
    };
    write_json_line(stdin, &response)
}

pub(super) fn write_json_line<T: serde::Serialize>(
    stdin: &mut ChildStdin,
    payload: &T,
) -> Result<(), String> {
    let encoded = serde_json::to_string(payload).map_err(|error| error.to_string())?;
    stdin
        .write_all(encoded.as_bytes())
        .and_then(|_| stdin.write_all(b"\n"))
        .and_then(|_| stdin.flush())
        .map_err(|error| format!("codex_app_server_write_failed:{error}"))
}

pub(super) fn json_rpc_id(value: &Value) -> Result<JsonRpcId, String> {
    match value.get("id") {
        Some(Value::Number(number)) => number
            .as_i64()
            .map(JsonRpcId::Number)
            .ok_or_else(|| "invalid_jsonrpc_id".to_string()),
        Some(Value::String(text)) => Ok(JsonRpcId::String(text.clone())),
        _ => Err("missing_jsonrpc_id".to_string()),
    }
}

pub(super) fn normalize_status(raw: &str) -> String {
    match raw.trim() {
        "inProgress" => "in_progress".to_string(),
        "completed" => "completed".to_string(),
        "failed" => "failed".to_string(),
        "declined" => "failed".to_string(),
        "started" => "started".to_string(),
        other => other.to_lowercase(),
    }
}

pub(super) fn first_result_text(value: Option<&Value>) -> Option<String> {
    value
        .and_then(|item| item.get("content"))
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|first| first.get("text"))
        .and_then(string_value)
}

pub(super) fn raw_string_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub(super) fn is_turn_completed(value: &Value) -> bool {
    value
        .get("method")
        .and_then(string_value)
        .map(|method| method == "turn/completed")
        .unwrap_or(false)
}

pub(super) fn spawn_stderr_collector(stderr: std::process::ChildStderr) -> Arc<Mutex<Vec<String>>> {
    let tail = Arc::new(Mutex::new(Vec::new()));
    let captured = Arc::clone(&tail);
    thread::spawn(move || {
        let reader = BufReader::new(stderr);
        for line in reader.lines().map_while(Result::ok) {
            let mut guard = captured.lock().unwrap();
            guard.push(line);
            if guard.len() > 20 {
                guard.remove(0);
            }
        }
    });
    tail
}

#[cfg(test)]
mod tests {
    use super::raw_string_field;
    use serde_json::json;

    #[test]
    fn raw_string_field_preserves_whitespace_and_newlines() {
        let payload = json!({
            "delta": " Ho aggiornato la todo list.\nPoi ho aperto il plan panel. "
        });

        assert_eq!(
            raw_string_field(&payload, "delta").as_deref(),
            Some(" Ho aggiornato la todo list.\nPoi ho aperto il plan panel. ")
        );
    }
}
