use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandPlanRequest {
    pub schema_version: i32,
    pub action: String,
    pub session_id: Option<String>,
    #[serde(default)]
    pub payload: HashMap<String, String>,
    pub workspace_available: bool,
    pub snapshot_exists: bool,
    pub current_config: Option<ReviewCommandConfig>,
    pub default_config: ReviewCommandConfig,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandConfig {
    pub max_workers: i32,
    pub max_rounds: i32,
    pub analysis_backend: String,
    pub execution_backend: String,
    pub analysis_only: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandPlanResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub kind: String,
    pub message: Option<String>,
    pub session_id: Option<String>,
    pub config: Option<ReviewCommandConfig>,
    pub action: Option<String>,
    pub finding_id: Option<String>,
    pub reason: Option<String>,
    pub author: Option<String>,
    pub content: Option<String>,
    pub deferred: bool,
}

impl ReviewCommandPlanResponse {
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            kind: "error".to_string(),
            message: Some(message.into()),
            session_id: None,
            config: None,
            action: None,
            finding_id: None,
            reason: None,
            author: None,
            content: None,
            deferred: false,
        }
    }

    pub fn success(kind: &str) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            kind: kind.to_string(),
            message: None,
            session_id: None,
            config: None,
            action: None,
            finding_id: None,
            reason: None,
            author: None,
            content: None,
            deferred: false,
        }
    }
}
