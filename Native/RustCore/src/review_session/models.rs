use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSessionSnapshotNewRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub config: Option<Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSessionActionRequest {
    pub schema_version: i32,
    pub operation: String,
    pub snapshot: Value,
    pub scope: Option<Value>,
    pub workspace_path: Option<String>,
    pub finding: Option<Value>,
    pub findings: Option<Vec<Value>>,
    pub candidate: Option<Value>,
    pub candidates: Option<Vec<Value>>,
    pub candidate_id: Option<String>,
    pub finding_id: Option<String>,
    pub patch: Option<Value>,
    pub reason: Option<String>,
    pub comment: Option<Value>,
    pub config: Option<Value>,
    pub round: Option<i64>,
    pub count: Option<i64>,
    pub phase: Option<String>,
    pub stage: Option<String>,
    pub job_id: Option<String>,
    pub tool_name: Option<String>,
    pub audit_result: Option<Value>,
    pub worker_id: Option<String>,
    pub title: Option<String>,
    pub status: Option<String>,
    pub method: Option<String>,
    pub report: Option<String>,
    pub false_positive_reason: Option<String>,
    pub result_detail: Option<String>,
    pub test_status: Option<String>,
    pub files: Option<Vec<String>>,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRegistryActionRequest {
    pub schema_version: i32,
    pub operation: String,
    pub snapshot: Value,
    #[serde(default)]
    pub payload: HashMap<String, String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSessionResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub snapshot: Option<Value>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSessionProjectionResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub projection: Option<Value>,
}

impl ReviewSessionResponse {
    pub fn success(snapshot: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            snapshot: Some(snapshot),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            snapshot: None,
        }
    }
}

impl ReviewSessionProjectionResponse {
    pub fn success(projection: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            projection: Some(projection),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            projection: None,
        }
    }
}
