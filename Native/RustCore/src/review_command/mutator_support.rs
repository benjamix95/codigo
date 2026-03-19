use super::models::ReviewCommandMutationResponse;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn required(
    payload: &HashMap<String, String>,
    key: &str,
) -> Result<String, ReviewCommandMutationResponse> {
    payload
        .get(key)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ReviewCommandMutationResponse::error(format!("Missing {}", key)))
}

pub fn find_finding<'a>(
    findings: &'a mut [Value],
    finding_id: &str,
) -> Result<&'a mut Value, ReviewCommandMutationResponse> {
    findings
        .iter_mut()
        .find(|finding| finding.get("id").and_then(Value::as_str) == Some(finding_id))
        .ok_or_else(|| ReviewCommandMutationResponse::error("Finding not found"))
}

pub fn find_patch<'a>(patches: &'a [Value], finding_id: &str) -> Option<&'a Value> {
    patches
        .iter()
        .find(|patch| patch.get("findingId").and_then(Value::as_str) == Some(finding_id))
}

pub fn reference_timestamp(snapshot: &Value) -> f64 {
    snapshot
        .get("lastUpdatedAt")
        .and_then(Value::as_f64)
        .unwrap_or_else(now_reference_seconds)
}

pub fn now_reference_seconds() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}

pub fn event_with_reference_timestamp(
    event_type: &str,
    detail: String,
    metadata: Value,
    timestamp: f64,
) -> Value {
    json!({
        "id": format!("command-event-{}-{timestamp:.6}", event_type),
        "type": event_type,
        "timestamp": timestamp,
        "detail": detail,
        "metadata": metadata,
    })
}
