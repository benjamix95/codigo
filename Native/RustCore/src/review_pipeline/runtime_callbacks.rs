use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeTestsReductionRequest {
    pub schema_version: i32,
    pub result: String,
    pub detail: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimePatchReductionRequest {
    pub schema_version: i32,
    pub current_snapshot: Value,
    pub updated_snapshot: Value,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeReductionResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub callback: Option<Value>,
}

impl ReviewRuntimeReductionResponse {
    pub fn success(callback: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            callback: Some(callback),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            callback: None,
        }
    }
}

pub fn reduce_tests_callback(
    request: ReviewRuntimeTestsReductionRequest,
) -> ReviewRuntimeReductionResponse {
    if request.schema_version != 1 {
        return ReviewRuntimeReductionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let request_detail = request.detail.clone();
    let result = request.result.as_str();
    let (test_status, event_type, detail) = match result {
        "passed" => (
            "passed",
            "tests_passed",
            request_detail
                .clone()
                .unwrap_or_else(|| "Tests passed".to_string()),
        ),
        "failed" => (
            "failed",
            "tests_failed",
            request_detail
                .clone()
                .unwrap_or_else(|| "Tests failed".to_string()),
        ),
        "inconclusive" => (
            "inconclusive",
            "tests_failed",
            request_detail
                .clone()
                .unwrap_or_else(|| "Tests inconclusive".to_string()),
        ),
        _ => {
            return ReviewRuntimeReductionResponse::error(
                "unsupported_result",
                "Unsupported test result kind",
            )
        }
    };
    let detail_value = if test_status == "inconclusive" {
        request_detail.map(Value::String).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    let callback = json!({
        "kind": "run_tests",
        "events": [make_event(event_type, detail, json!({}))],
        "testStatus": test_status,
        "detail": detail_value,
    });
    ReviewRuntimeReductionResponse::success(callback)
}

pub fn reduce_prepare_verified_patches_callback(
    request: ReviewRuntimePatchReductionRequest,
) -> ReviewRuntimeReductionResponse {
    if request.schema_version != 1 {
        return ReviewRuntimeReductionResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let current_events = request
        .current_snapshot
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let updated_events = request
        .updated_snapshot
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if updated_events.len() < current_events.len() {
        return ReviewRuntimeReductionResponse::error(
            "invalid_snapshot_delta",
            "Updated snapshot has fewer events than the current snapshot",
        );
    }
    let delta_events = updated_events
        .into_iter()
        .skip(current_events.len())
        .collect::<Vec<_>>();
    let callback = json!({
        "kind": "prepare_verified_patches",
        "findings": request.updated_snapshot.get("findings").cloned().unwrap_or_else(|| json!([])),
        "patches": request.updated_snapshot.get("patches").cloned().unwrap_or_else(|| json!([])),
        "events": delta_events,
    });
    ReviewRuntimeReductionResponse::success(callback)
}

fn make_event(event_type: &str, detail: String, metadata: Value) -> Value {
    let timestamp = apple_reference_seconds();
    json!({
        "id": format!("runtime-event-{event_type}-{timestamp:.6}"),
        "type": event_type,
        "timestamp": timestamp,
        "detail": detail,
        "metadata": metadata.as_object().cloned().unwrap_or_default(),
    })
}

fn apple_reference_seconds() -> f64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reduce_tests_callback_emits_expected_status_and_event() {
        let response = reduce_tests_callback(ReviewRuntimeTestsReductionRequest {
            schema_version: 1,
            result: "inconclusive".to_string(),
            detail: Some("timed out".to_string()),
        });
        let callback = response.callback.unwrap();
        assert_eq!(callback["kind"].as_str(), Some("run_tests"));
        assert_eq!(callback["testStatus"].as_str(), Some("inconclusive"));
        assert_eq!(callback["detail"].as_str(), Some("timed out"));
        assert_eq!(callback["events"][0]["type"].as_str(), Some("tests_failed"));
    }

    #[test]
    fn reduce_patch_callback_returns_delta_events_only() {
        let response = reduce_prepare_verified_patches_callback(
            ReviewRuntimePatchReductionRequest {
                schema_version: 1,
                current_snapshot: json!({
                    "events": [{"id":"old","type":"analysis_completed","timestamp":1.0,"detail":"old","metadata":{}}]
                }),
                updated_snapshot: json!({
                    "findings": [{"id":"finding-1"}],
                    "patches": [{"id":"patch-1"}],
                    "events": [
                        {"id":"old","type":"analysis_completed","timestamp":1.0,"detail":"old","metadata":{}},
                        {"id":"new","type":"patch_prepared","timestamp":2.0,"detail":"new","metadata":{}}
                    ]
                }),
            },
        );
        let callback = response.callback.unwrap();
        assert_eq!(callback["events"].as_array().unwrap().len(), 1);
        assert_eq!(callback["events"][0]["id"].as_str(), Some("new"));
        assert_eq!(callback["patches"][0]["id"].as_str(), Some("patch-1"));
    }
}
