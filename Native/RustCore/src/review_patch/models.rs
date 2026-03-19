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
pub struct ReviewPatchPrepareContextRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub finding_id: String,
    pub file_path: String,
    pub line_number: Option<i32>,
    pub message: String,
    pub verification_report: Option<String>,
    pub suggested_fix: Option<String>,
    pub expected_invariant: Option<String>,
    pub repro_or_reasoning: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchVerifyResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub finding_id: String,
    pub success: bool,
    pub error_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchApplyResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub finding_id: String,
    pub success: bool,
    pub validation_run_id: Option<String>,
    pub validation_status: Option<String>,
    pub validation_summary: Option<String>,
    pub error_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRevalidateResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub validation_run_id: Option<String>,
    pub validation_status: Option<String>,
    pub validation_summary: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRollbackResultRequest {
    pub schema_version: i32,
    pub patch_id: String,
    pub success: bool,
    pub error_message: Option<String>,
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

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchPrepareContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub branch_name: Option<String>,
    pub prompt: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchVerifyResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub verify_status: Option<String>,
    pub conflicts: Option<Vec<String>>,
    pub apply_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchApplyResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub verify_status: Option<String>,
    pub rollback_ref: Option<String>,
    pub validation_run_id: Option<String>,
    pub validation_status: Option<String>,
    pub validation_summary: Option<String>,
    pub apply_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRevalidateResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub validation_run_id: Option<String>,
    pub validation_status: Option<String>,
    pub validation_summary: Option<String>,
    pub apply_message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchRollbackResultResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub status: Option<String>,
    pub apply_message: Option<String>,
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

impl ReviewPatchPrepareContextResponse {
    pub fn success(branch_name: String, prompt: String) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            branch_name: Some(branch_name),
            prompt: Some(prompt),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            branch_name: None,
            prompt: None,
        }
    }
}

impl ReviewPatchVerifyResultResponse {
    pub fn success(
        status: String,
        verify_status: String,
        conflicts: Vec<String>,
        apply_message: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            verify_status: Some(verify_status),
            conflicts: Some(conflicts),
            apply_message,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            verify_status: None,
            conflicts: None,
            apply_message: None,
        }
    }
}

impl ReviewPatchApplyResultResponse {
    pub fn success(
        status: String,
        verify_status: String,
        rollback_ref: String,
        validation_run_id: Option<String>,
        validation_status: String,
        validation_summary: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            verify_status: Some(verify_status),
            rollback_ref: Some(rollback_ref),
            validation_run_id,
            validation_status: Some(validation_status),
            validation_summary: validation_summary.clone(),
            apply_message: validation_summary,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            verify_status: None,
            rollback_ref: None,
            validation_run_id: None,
            validation_status: None,
            validation_summary: None,
            apply_message: None,
        }
    }
}

impl ReviewPatchRevalidateResultResponse {
    pub fn success(
        status: String,
        validation_run_id: Option<String>,
        validation_status: String,
        validation_summary: Option<String>,
        apply_message: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            validation_run_id,
            validation_status: Some(validation_status),
            validation_summary,
            apply_message,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            validation_run_id: None,
            validation_status: None,
            validation_summary: None,
            apply_message: None,
        }
    }
}

impl ReviewPatchRollbackResultResponse {
    pub fn success(status: String, apply_message: String) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            status: Some(status),
            apply_message: Some(apply_message),
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            status: None,
            apply_message: None,
        }
    }
}
