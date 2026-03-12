use super::models::ReviewCommandConfig;
use serde_json::Value;
use std::collections::HashMap;

pub fn resolve_config_from_payload(
    payload: &HashMap<String, String>,
    fallback: ReviewCommandConfig,
) -> ReviewCommandConfig {
    ReviewCommandConfig {
        max_workers: payload
            .get("max_workers")
            .and_then(|value| value.trim().parse::<i32>().ok())
            .unwrap_or(fallback.max_workers),
        max_rounds: payload
            .get("max_rounds")
            .and_then(|value| value.trim().parse::<i32>().ok())
            .unwrap_or(fallback.max_rounds),
        analysis_backend: non_empty(payload.get("analysis_backend"))
            .unwrap_or(fallback.analysis_backend),
        execution_backend: non_empty(payload.get("execution_backend"))
            .unwrap_or(fallback.execution_backend),
        analysis_only: payload
            .get("analysis_only")
            .and_then(|value| parse_bool(value))
            .unwrap_or(fallback.analysis_only),
    }
}

pub fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_lowercase().as_str() {
        "1" | "true" | "yes" | "y" => Some(true),
        "0" | "false" | "no" | "n" => Some(false),
        _ => None,
    }
}

pub fn sanitize_session_id(session_id: Option<String>) -> Option<String> {
    let session_id = session_id
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())?;
    let mut chars = session_id.chars();
    let first = chars.next()?;
    if !first.is_ascii_alphanumeric() || session_id.len() > 128 {
        return None;
    }
    if chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_') {
        Some(session_id)
    } else {
        None
    }
}

pub fn config_from_snapshot(snapshot: &Value) -> Result<ReviewCommandConfig, String> {
    let Some(config) = snapshot.get("config") else {
        return Err("Snapshot config is missing".to_string());
    };
    Ok(ReviewCommandConfig {
        max_workers: config
            .get("maxWorkers")
            .and_then(Value::as_i64)
            .unwrap_or(6) as i32,
        max_rounds: config
            .get("maxRounds")
            .and_then(Value::as_i64)
            .unwrap_or(3) as i32,
        analysis_backend: config
            .get("analysisBackend")
            .and_then(Value::as_str)
            .unwrap_or("codex")
            .to_string(),
        execution_backend: config
            .get("executionBackend")
            .and_then(Value::as_str)
            .unwrap_or("codex")
            .to_string(),
        analysis_only: config
            .get("analysisOnly")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

pub fn trim(value: Option<&String>) -> String {
    value.map(|value| value.trim().to_string()).unwrap_or_default()
}

pub fn non_empty(value: Option<&String>) -> Option<String> {
    let value = trim(value);
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}
