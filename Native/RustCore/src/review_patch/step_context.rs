use super::models::{ReviewPatchRecord, ReviewPatchSnapshot};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchStepContextRequest {
    pub schema_version: i32,
    pub step: String,
    pub finding_id: String,
    pub snapshot: ReviewPatchSnapshot,
    pub provider_registry_available: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPatchStepContextResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: Option<String>,
    pub patch: Option<serde_json::Value>,
    pub finding: Option<serde_json::Value>,
    pub provider_registry_required: bool,
}

pub fn build_step_context(
    request: ReviewPatchStepContextRequest,
) -> ReviewPatchStepContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchStepContextResponse::error("schemaVersion must be 1");
    }

    match request.step.as_str() {
        "prepare_patch" => {
            let finding = request
                .snapshot
                .findings
                .iter()
                .find(|finding| finding.id == request.finding_id)
                .cloned();
            match finding {
                Some(finding) => ReviewPatchStepContextResponse::success(
                    None,
                    Some(serde_json::to_value(finding).unwrap_or(serde_json::Value::Null)),
                    request.provider_registry_available,
                ),
                None => ReviewPatchStepContextResponse::error(
                    "Il finding non è verificato e non può produrre una patch applicabile.",
                ),
            }
        }
        "verify_patch" | "apply_patch" | "revalidate_finding" | "rollback_patch" => {
            match patch_for(&request.snapshot, &request.finding_id) {
                Some(patch) => ReviewPatchStepContextResponse::success(
                    Some(serde_json::to_value(patch).unwrap_or(serde_json::Value::Null)),
                    None,
                    false,
                ),
                None => ReviewPatchStepContextResponse::error(
                    "La patch salvata non è valida o non è applicabile al workspace corrente.",
                ),
            }
        }
        "open_pr" => {
            let patch = patch_for(&request.snapshot, &request.finding_id);
            let finding = request
                .snapshot
                .findings
                .iter()
                .find(|finding| finding.id == request.finding_id)
                .cloned();
            match (patch, finding) {
                (Some(patch), Some(finding)) => ReviewPatchStepContextResponse::success(
                    Some(serde_json::to_value(patch).unwrap_or(serde_json::Value::Null)),
                    Some(serde_json::to_value(finding).unwrap_or(serde_json::Value::Null)),
                    false,
                ),
                _ => ReviewPatchStepContextResponse::error(
                    "La patch salvata non è valida o non è applicabile al workspace corrente.",
                ),
            }
        }
        "merge_pr" | "resolve_conflicts" => {
            let patch = patch_for(&request.snapshot, &request.finding_id);
            match patch {
                Some(patch) => {
                    if !request.provider_registry_available {
                        return ReviewPatchStepContextResponse::error(
                            "Nessun provider agente disponibile per preparare la patch.",
                        );
                    }
                    ReviewPatchStepContextResponse::success(
                        Some(serde_json::to_value(patch).unwrap_or(serde_json::Value::Null)),
                        None,
                        true,
                    )
                }
                None => ReviewPatchStepContextResponse::error(
                    "La patch salvata non è valida o non è applicabile al workspace corrente.",
                ),
            }
        }
        "close_finding" => ReviewPatchStepContextResponse::success(None, None, false),
        _ => ReviewPatchStepContextResponse::success(None, None, false),
    }
}

fn patch_for(snapshot: &ReviewPatchSnapshot, finding_id: &str) -> Option<ReviewPatchRecord> {
    snapshot
        .patches
        .iter()
        .find(|patch| patch.finding_id == finding_id)
        .cloned()
}

impl ReviewPatchStepContextResponse {
    fn success(
        patch: Option<serde_json::Value>,
        finding: Option<serde_json::Value>,
        provider_registry_required: bool,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: None,
            patch,
            finding,
            provider_registry_required,
        }
    }

    pub fn error(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: Some(message.into()),
            patch: None,
            finding: None,
            provider_registry_required: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_patch::models::ReviewFindingRecord;

    fn snapshot() -> ReviewPatchSnapshot {
        ReviewPatchSnapshot {
            session_id: "session-1".to_string(),
            conversation_id: None,
            finding_ids: vec![],
            candidate_ids: vec![],
            patches: vec![ReviewPatchRecord {
                id: "patch-1".to_string(),
                finding_id: "finding-1".to_string(),
                status: "verified".to_string(),
                verify_status: "verified".to_string(),
                validation_status: "passed".to_string(),
                risk_score: 0.1,
            }],
            findings: vec![ReviewFindingRecord {
                id: "finding-1".to_string(),
                status: "open".to_string(),
                severity: "warning".to_string(),
                category: "correctness".to_string(),
                message: "Issue".to_string(),
                patch_artifact_id: None,
            }],
        }
    }

    #[test]
    fn build_step_context_returns_patch_for_apply_steps() {
        let response = build_step_context(ReviewPatchStepContextRequest {
            schema_version: 1,
            step: "apply_patch".to_string(),
            finding_id: "finding-1".to_string(),
            snapshot: snapshot(),
            provider_registry_available: false,
        });

        assert!(!response.is_error);
        assert!(response.patch.is_some());
    }

    #[test]
    fn build_step_context_requires_provider_for_merge() {
        let response = build_step_context(ReviewPatchStepContextRequest {
            schema_version: 1,
            step: "merge_pr".to_string(),
            finding_id: "finding-1".to_string(),
            snapshot: snapshot(),
            provider_registry_available: false,
        });

        assert!(response.is_error);
    }
}
