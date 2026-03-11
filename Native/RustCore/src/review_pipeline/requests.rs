use super::models::ReviewPipelineConfig;
use serde::Deserialize;
use serde_json::Value;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineStartRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub prompt: String,
    pub workspace_path: String,
    pub config: ReviewPipelineConfig,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineApplyRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub callback: ReviewPipelineCallbackResult,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineSessionRequest {
    pub schema_version: i32,
    pub session_id: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[allow(dead_code)]
pub struct ReviewPipelineCallbackResult {
    pub kind: String,
    #[serde(default)]
    pub files: Vec<String>,
    #[serde(default)]
    pub findings: Vec<Value>,
    #[serde(default)]
    pub candidates: Vec<Value>,
    #[serde(default)]
    pub promoted_findings: Vec<Value>,
    #[serde(default)]
    pub events: Vec<Value>,
    pub audit: Option<Value>,
    pub text: Option<String>,
    pub error: Option<String>,
    pub test_status: Option<String>,
    pub detail: Option<String>,
}
