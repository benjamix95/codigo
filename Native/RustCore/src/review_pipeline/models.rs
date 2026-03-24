use super::ledger::{ReviewPipelineFileLedgerEntry, ReviewPipelinePhaseLedgerEntry};
use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineConfig {
    pub max_workers: i32,
    pub max_review_rounds: i32,
    pub enabled_phases: String,
    pub analysis_backend: String,
    pub execution_backend: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub session_id: String,
    pub snapshot: ReviewPipelineSnapshot,
    pub step: ReviewPipelineStep,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineStep {
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clean_prompt: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scope_description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub against_ref: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resolved_scope: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub files: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub finding_ids: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tasks: Vec<ReviewTask>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub round: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_workers: Option<i32>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineSnapshot {
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub mutation_sequence: u64,
    pub phase: String,
    pub stage: String,
    pub findings: Vec<Value>,
    pub candidates: Vec<Value>,
    pub patches: Vec<Value>,
    pub events: Vec<Value>,
    pub config: ReviewPipelineConfig,
    pub scope: Option<ReviewPipelineScope>,
    pub workspace_path: Option<String>,
    pub current_round: i32,
    pub active_worker_count: i32,
    pub started_at: Option<f64>,
    pub completed_at: Option<f64>,
    pub analysis_completed_at: Option<f64>,
    pub last_error: Option<String>,
    pub current_job_id: Option<String>,
    pub last_test_status: Option<String>,
    pub audit: Value,
    pub outcome: Value,
    pub verified_findings: Option<Value>,
    pub phase_ledger: Vec<ReviewPipelinePhaseLedgerEntry>,
    pub file_ledger: Vec<ReviewPipelineFileLedgerEntry>,
    pub last_updated_at: f64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPipelineScope {
    pub r#type: String,
    pub files: Vec<String>,
    pub r#ref: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewTask {
    pub id: String,
    pub description: String,
    pub files: Vec<String>,
    pub severity: String,
    pub category: Option<String>,
    pub line_number: Option<i32>,
    pub end_line_number: Option<i32>,
    pub origin: String,
    pub confidence: Option<f64>,
    pub evidence: Option<String>,
    pub expected_invariant: Option<String>,
    pub repro_or_reasoning: Option<String>,
    pub source_tool: Option<String>,
    pub blocking: Option<bool>,
}

impl ReviewPipelineResponse {
    pub fn success(
        session_id: String,
        snapshot: ReviewPipelineSnapshot,
        step: ReviewPipelineStep,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            session_id,
            snapshot,
            step,
        }
    }

    pub fn error(
        session_id: String,
        snapshot: ReviewPipelineSnapshot,
        code: &str,
        message: &str,
    ) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            session_id,
            snapshot,
            step: ReviewPipelineStep::failed(message),
        }
    }
}

impl ReviewPipelineStep {
    pub fn resolve_scope_files(
        clean_prompt: String,
        resolved_scope: String,
        against_ref: Option<String>,
    ) -> Self {
        Self {
            kind: "resolve_scope_files".to_string(),
            clean_prompt: Some(clean_prompt),
            scope_description: None,
            against_ref,
            resolved_scope: Some(resolved_scope),
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn run_audit(files: Vec<String>) -> Self {
        Self {
            kind: "run_audit_stage".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files,
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn analysis(
        clean_prompt: String,
        scope_description: String,
        files: Vec<String>,
        max_workers: i32,
    ) -> Self {
        Self {
            kind: "request_analysis_stream".to_string(),
            clean_prompt: Some(clean_prompt),
            scope_description: Some(scope_description),
            against_ref: None,
            resolved_scope: None,
            files,
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: Some(max_workers),
        }
    }

    pub fn prepare_task_candidates(tasks: Vec<ReviewTask>, files: Vec<String>, round: i32) -> Self {
        Self {
            kind: "prepare_task_candidates".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files,
            finding_ids: Vec::new(),
            tasks,
            round: Some(round),
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn fix_stage(
        tasks: Vec<ReviewTask>,
        round: i32,
        resolved_scope: String,
        against_ref: Option<String>,
    ) -> Self {
        Self {
            kind: "run_fix_stage".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref,
            resolved_scope: Some(resolved_scope),
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks,
            round: Some(round),
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn run_tests() -> Self {
        Self {
            kind: "run_tests".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn scan_modified_files() -> Self {
        Self {
            kind: "scan_modified_files".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn rereview(files: Vec<String>, round: i32, max_workers: i32) -> Self {
        Self {
            kind: "request_rereview_stream".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files,
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: Some(round),
            reason: None,
            message: None,
            max_workers: Some(max_workers),
        }
    }

    pub fn prepare_verified_patches(finding_ids: Vec<String>) -> Self {
        Self {
            kind: "prepare_verified_patches".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files: Vec::new(),
            finding_ids,
            tasks: Vec::new(),
            round: None,
            reason: None,
            message: None,
            max_workers: None,
        }
    }

    pub fn completed(message: Option<String>) -> Self {
        Self {
            kind: "completed".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: None,
            message,
            max_workers: None,
        }
    }

    pub fn failed(reason: impl Into<String>) -> Self {
        Self {
            kind: "failed".to_string(),
            clean_prompt: None,
            scope_description: None,
            against_ref: None,
            resolved_scope: None,
            files: Vec::new(),
            finding_ids: Vec::new(),
            tasks: Vec::new(),
            round: None,
            reason: Some(reason.into()),
            message: None,
            max_workers: None,
        }
    }
}
