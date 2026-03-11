use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreErrorPayload {
    pub code: String,
    pub message: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreListResponse<T: Serialize> {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub results: Option<Vec<T>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreSyncResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub findings: Vec<Value>,
    pub projection: Value,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreAuditResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub result: Option<Value>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreReduceResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub merged_history: Vec<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panel_state: Option<Value>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreProjectionResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub projection: Value,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreReplayResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub report: Option<Value>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCoreSecurityGateResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub report: Option<Value>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewVerificationResultPayload {
    pub candidate_id: String,
    pub status: String,
    pub method: String,
    pub report: String,
    pub false_positive_reason: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewVerifyRequest {
    pub schema_version: i32,
    pub candidates: Vec<Value>,
    pub workspace_path: String,
    pub scope_files: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSyncRequest {
    pub schema_version: i32,
    pub findings: Vec<Value>,
    pub trace_log: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewAuditRequest {
    pub schema_version: i32,
    pub tool_name: String,
    pub scope_files: Vec<String>,
    pub workspace_path: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewReduceRequest {
    pub schema_version: i32,
    pub operation: String,
    pub primary: Option<Vec<Value>>,
    pub fallback: Option<Vec<Value>>,
    pub snapshot: Option<Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewProjectionRequest {
    pub schema_version: i32,
    pub findings: Vec<Value>,
    pub trace_log: Vec<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewReplayRequest {
    pub schema_version: i32,
    pub envelope: Value,
    pub checkpoint_source: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSecurityGateRequest {
    pub schema_version: i32,
    pub envelope: Value,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewHistoricalShapeRequest {
    pub schema_version: i32,
    pub records: Vec<Value>,
}

impl ReviewCoreErrorPayload {
    pub fn new(code: &str, message: &str) -> Self {
        Self {
            code: code.to_string(),
            message: message.to_string(),
        }
    }
}

impl<T: Serialize> ReviewCoreListResponse<T> {
    pub fn success(results: Vec<T>) -> Self {
        Self {
            schema_version: 1,
            error: None,
            results: Some(results),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            results: None,
        }
    }
}

impl ReviewCoreSyncResponse {
    pub fn success(findings: Vec<Value>, projection: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            findings,
            projection,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            findings: Vec::new(),
            projection: Value::Null,
        }
    }
}

impl ReviewCoreAuditResponse {
    pub fn success(result: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            result: Some(result),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            result: None,
        }
    }
}

impl ReviewCoreReduceResponse {
    pub fn success(merged_history: Vec<Value>) -> Self {
        Self {
            schema_version: 1,
            error: None,
            merged_history,
            panel_state: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            merged_history: Vec::new(),
            panel_state: None,
        }
    }

    pub fn success_panel_state(panel_state: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            merged_history: Vec::new(),
            panel_state: Some(panel_state),
        }
    }
}

impl ReviewCoreProjectionResponse {
    pub fn success(projection: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            projection,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            projection: Value::Null,
        }
    }
}

impl ReviewCoreReplayResponse {
    pub fn success(report: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            report: Some(report),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            report: None,
        }
    }
}

impl ReviewCoreSecurityGateResponse {
    pub fn success(report: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            report: Some(report),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            report: None,
        }
    }
}
