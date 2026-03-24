use crate::review_mcp::commands::build_review_index;
use crate::review_mcp::models::{
    CommandRecord, ReviewMCPIndexRequest, ReviewMCPIndexResponse, ReviewSnapshotRecord,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPersistencePayloadRequest {
    pub schema_version: i32,
    pub payload: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPersistenceIndexRequest {
    pub schema_version: i32,
    #[serde(default)]
    pub review_snapshots: Vec<ReviewSnapshotRecord>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPersistencePayloadResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub error_message: Option<String>,
    pub payload: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPersistenceIndexResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub error_message: Option<String>,
    pub latest_session_id: Option<String>,
    #[serde(default)]
    pub latest_session_id_by_conversation: std::collections::HashMap<String, String>,
    #[serde(default)]
    pub sessions: Vec<crate::review_mcp::models::ReviewSnapshotIndexRecord>,
}

pub fn normalize_json_payload<T: serde::de::DeserializeOwned + serde::Serialize>(
    payload: &str,
) -> ReviewPersistencePayloadResponse {
    match serde_json::from_str::<T>(payload) {
        Ok(value) => match serde_json::to_string(&value) {
            Ok(payload) => ReviewPersistencePayloadResponse::ok(payload),
            Err(err) => ReviewPersistencePayloadResponse::err(&err.to_string()),
        },
        Err(err) => ReviewPersistencePayloadResponse::err(&err.to_string()),
    }
}

pub fn normalize_json_array_payload<T: serde::de::DeserializeOwned + serde::Serialize>(
    payload: &str,
) -> ReviewPersistencePayloadResponse {
    match serde_json::from_str::<Vec<T>>(payload) {
        Ok(value) => match serde_json::to_string(&value) {
            Ok(payload) => ReviewPersistencePayloadResponse::ok(payload),
            Err(err) => ReviewPersistencePayloadResponse::err(&err.to_string()),
        },
        Err(err) => ReviewPersistencePayloadResponse::err(&err.to_string()),
    }
}

pub fn build_index_response(
    request: ReviewPersistenceIndexRequest,
) -> ReviewPersistenceIndexResponse {
    let response: ReviewMCPIndexResponse = build_review_index(ReviewMCPIndexRequest {
        schema_version: request.schema_version,
        review_snapshots: request.review_snapshots,
    });
    ReviewPersistenceIndexResponse {
        schema_version: 1,
        is_error: false,
        error_message: None,
        latest_session_id: response.latest_session_id,
        latest_session_id_by_conversation: response.latest_session_id_by_conversation,
        sessions: response.sessions,
    }
}

impl ReviewPersistencePayloadResponse {
    pub fn ok(payload: String) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            error_message: None,
            payload: Some(payload),
        }
    }

    pub fn err(message: &str) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            error_message: Some(message.to_string()),
            payload: None,
        }
    }
}

pub type ReviewCommandRecord = CommandRecord;
pub type BugHunterCommandRecord = CommandRecord;
pub type ReviewSnapshotValue = Value;
pub type BugHunterSnapshotValue = Value;
