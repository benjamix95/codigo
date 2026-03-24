use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn session_started_event(
    scope: &str,
    file_count: usize,
    session_id: &str,
    sequence: u64,
    now: f64,
) -> Value {
    json!({
        "id": format!("{session_id}-evt-{sequence}"),
        "type": "session_started",
        "timestamp": now,
        "detail": format!("Review started with scope: {scope}"),
        "metadata": {
            "scope": scope,
            "file_count": file_count.to_string()
        }
    })
}

pub fn is_open_status(status: &str) -> bool {
    matches!(
        status,
        "open"
            | "patch_preparing"
            | "patch_ready"
            | "patch_applying"
            | "patch_failed"
            | "pr_opened"
            | "blocked"
    )
}

pub fn apple_reference_seconds() -> f64 {
    let unix = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_secs_f64())
        .unwrap_or(0.0);
    unix - 978_307_200.0
}
