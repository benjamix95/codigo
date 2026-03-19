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

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandMutationRequest {
    pub schema_version: i32,
    pub action: String,
    pub snapshot: serde_json::Value,
    #[serde(default)]
    pub payload: HashMap<String, String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewDeferredCommandFinalizeRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub phase: String,
    pub last_error: Option<String>,
    pub auto_prepare_succeeded: bool,
    pub source_state_succeeded: bool,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandPromptRequest {
    pub schema_version: i32,
    pub session_id: String,
    #[serde(default)]
    pub payload: HashMap<String, String>,
    pub config: ReviewCommandConfig,
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

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandMutationResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub config: Option<ReviewCommandConfig>,
    pub findings: Option<Vec<serde_json::Value>>,
    pub events: Option<Vec<serde_json::Value>>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewDeferredCommandFinalizeResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub command_status: String,
    pub result_message: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCommandPromptResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub prompt: Option<String>,
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

impl ReviewCommandMutationResponse {
    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            config: None,
            findings: None,
            events: None,
        }
    }

    pub fn success(
        findings: Vec<serde_json::Value>,
        events: Vec<serde_json::Value>,
        config: Option<ReviewCommandConfig>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            config,
            findings: Some(findings),
            events: Some(events),
        }
    }
}

impl ReviewDeferredCommandFinalizeResponse {
    pub fn success(status: &str, message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            command_status: status.to_string(),
            result_message: message.into(),
        }
    }
}

impl ReviewCommandPromptResponse {
    pub fn success(prompt: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            prompt: Some(prompt.into()),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            prompt: None,
        }
    }
}
