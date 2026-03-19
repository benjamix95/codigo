use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchActionRequest {
    pub schema_version: i32,
    pub operation: String,
    pub action: String,
    pub session_id: String,
    pub finding_id: String,
    pub conversation_id: Option<String>,
    pub snapshot: ReviewPatchSnapshot,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRuntimeStartRequest {
    pub schema_version: i32,
    pub action: String,
    pub session_id: String,
    pub finding_id: String,
    pub conversation_id: Option<String>,
    pub snapshot: ReviewPatchSnapshot,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRuntimeResultRequest {
    pub schema_version: i32,
    pub runtime_id: String,
    pub succeeded: bool,
    pub error_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRuntimeStateRequest {
    pub schema_version: i32,
    pub runtime_id: String,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchSnapshot {
    pub session_id: String,
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub finding_ids: Vec<String>,
    #[serde(default)]
    pub candidate_ids: Vec<String>,
    #[serde(default)]
    pub patches: Vec<ReviewPatchRecord>,
    #[serde(default)]
    pub findings: Vec<ReviewFindingRecord>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRecord {
    pub id: String,
    pub finding_id: String,
    pub status: String,
    pub verify_status: String,
    pub validation_status: String,
    pub risk_score: f64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewFindingRecord {
    pub id: String,
    pub status: String,
    pub severity: String,
    pub category: String,
    pub message: String,
    pub patch_artifact_id: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchActionResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub steps: Vec<String>,
    pub patch_id: Option<String>,
    pub patch_verify_status: Option<String>,
    pub patch_risk_score: Option<f64>,
    pub finding_severity: Option<String>,
    pub finding_category: Option<String>,
    pub finding_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRuntimeResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub action: Option<String>,
    pub session_id: Option<String>,
    pub finding_id: Option<String>,
    pub conversation_id: Option<String>,
    pub runtime_id: Option<String>,
    pub status: String,
    pub current_step: Option<String>,
    pub steps: Vec<String>,
    pub completed_steps: Vec<String>,
    pub last_transition_at: Option<f64>,
    pub terminal_reason: Option<String>,
}

impl ReviewPatchActionResponse {
    pub fn ok(
        steps: Vec<String>,
        patch: Option<&ReviewPatchRecord>,
        finding: Option<&ReviewFindingRecord>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            error_code: None,
            error_message: None,
            steps,
            patch_id: patch.map(|patch| patch.id.clone()),
            patch_verify_status: patch.map(|patch| patch.verify_status.clone()),
            patch_risk_score: patch.map(|patch| patch.risk_score),
            finding_severity: finding.map(|finding| finding.severity.clone()),
            finding_category: finding.map(|finding| finding.category.clone()),
            finding_message: finding.map(|finding| finding.message.clone()),
        }
    }

    pub fn err(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            error_code: Some(code.to_string()),
            error_message: Some(message.to_string()),
            steps: Vec::new(),
            patch_id: None,
            patch_verify_status: None,
            patch_risk_score: None,
            finding_severity: None,
            finding_category: None,
            finding_message: None,
        }
    }
}

impl ReviewPatchRuntimeResponse {
    pub fn ok(
        runtime_id: String,
        action: String,
        session_id: String,
        finding_id: String,
        conversation_id: Option<String>,
        status: &str,
        current_step: Option<String>,
        steps: Vec<String>,
        completed_steps: Vec<String>,
        last_transition_at: Option<f64>,
        terminal_reason: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            error_code: None,
            error_message: None,
            action: Some(action),
            session_id: Some(session_id),
            finding_id: Some(finding_id),
            conversation_id,
            runtime_id: Some(runtime_id),
            status: status.to_string(),
            current_step,
            steps,
            completed_steps,
            last_transition_at,
            terminal_reason,
        }
    }

    pub fn err(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            error_code: Some(code.to_string()),
            error_message: Some(message.to_string()),
            action: None,
            session_id: None,
            finding_id: None,
            conversation_id: None,
            runtime_id: None,
            status: "failed".to_string(),
            current_step: None,
            steps: Vec::new(),
            completed_steps: Vec::new(),
            last_transition_at: None,
            terminal_reason: None,
        }
    }
}
