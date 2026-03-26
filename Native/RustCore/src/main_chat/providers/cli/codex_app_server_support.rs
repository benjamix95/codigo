use crate::main_chat::providers::common::string_value;
use app_core_protocol::jsonrpc::{JsonRpcErrorResponse, JsonRpcId, JsonRpcResponse};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Write};
use std::process::ChildStdin;
use std::sync::{Arc, Mutex};
use std::thread;

fn truncate_utf8_prefix(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut end = max;
    while end > 0 && !s.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…", &s[..end])
}

/// Params notifica app-server (oggetti annidati → `*_json` troncati) per `emit_raw` verso Swift.
pub(super) fn flatten_app_server_params_to_payload(
    payload: &Value,
    max_nested: usize,
) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let Some(obj) = payload.as_object() else {
        if let Ok(s) = serde_json::to_string(payload) {
            out.insert("payload_json".to_string(), truncate_utf8_prefix(&s, max_nested));
        }
        return out;
    };
    for (k, v) in obj {
        match v {
            Value::String(s) => {
                out.insert(k.clone(), s.clone());
            }
            Value::Number(n) => {
                out.insert(k.clone(), n.to_string());
            }
            Value::Bool(b) => {
                out.insert(k.clone(), b.to_string());
            }
            Value::Null => {}
            _ => {
                if let Ok(s) = serde_json::to_string(v) {
                    out.insert(format!("{k}_json"), truncate_utf8_prefix(&s, max_nested));
                }
            }
        }
    }
    out
}

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
            if guard.len() > 80 {
                guard.remove(0);
            }
        }
    });
    tail
}

/// Aggiunge stato figlio e ultime righe stderr a qualsiasi errore del path app-server
/// (utile quando `Broken pipe` indica che Codex è uscito ma l'errore reale è solo su stderr).
pub(super) fn enrich_codex_process_error(
    error: String,
    stderr_tail: &Arc<Mutex<Vec<String>>>,
    child: &mut std::process::Child,
) -> String {
    let status_note = match child.try_wait() {
        Ok(Some(status)) => format!("codex_child_exited:code={:?}", status.code()),
        Ok(None) => "codex_child_still_running_or_unknown".to_string(),
        Err(e) => format!("codex_try_wait_failed:{e}"),
    };
    let tail = stderr_tail
        .lock()
        .map(|lines| lines.join("\n"))
        .unwrap_or_default();
    let trimmed = tail.trim();
    if trimmed.is_empty() {
        return format!("{error}\n{status_note}");
    }
    format!("{error}\n{status_note}\ncodex_stderr_tail:\n{trimmed}")
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

    #[test]
    fn flatten_app_server_params_nested_becomes_json_key() {
        use super::flatten_app_server_params_to_payload;
        let v = json!({"threadId": "t1", "meta": {"a": 1}});
        let m = flatten_app_server_params_to_payload(&v, 500);
        assert_eq!(m.get("threadId").map(String::as_str), Some("t1"));
        assert!(m.contains_key("meta_json"));
    }
}
