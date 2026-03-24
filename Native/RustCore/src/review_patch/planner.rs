use super::models::{
    ReviewFindingRecord, ReviewPatchActionRequest, ReviewPatchActionResponse, ReviewPatchRecord,
};

pub fn handle_patch_action(request: ReviewPatchActionRequest) -> ReviewPatchActionResponse {
    if request.session_id.trim().is_empty() || request.finding_id.trim().is_empty() {
        return ReviewPatchActionResponse::err(
            "missing_identifiers",
            "finding_id and session_id are required",
        );
    }
    if request.snapshot.session_id != request.session_id {
        return ReviewPatchActionResponse::err(
            "session_not_found",
            &format!("session_id '{}' was not found", request.session_id),
        );
    }
    if let Some(snapshot_conversation_id) = request.snapshot.conversation_id.as_ref() {
        match request.conversation_id.as_ref() {
            None => {
                return ReviewPatchActionResponse::err(
                    "conversation_required",
                    &format!(
                        "conversation_id is required for session_id '{}'",
                        request.session_id
                    ),
                );
            }
            Some(conversation_id) if conversation_id != snapshot_conversation_id => {
                return ReviewPatchActionResponse::err(
                    "conversation_mismatch",
                    &format!(
                        "session_id '{}' does not belong to the requested conversation",
                        request.session_id
                    ),
                );
            }
            _ => {}
        }
    }

    let owned = request
        .snapshot
        .finding_ids
        .iter()
        .any(|id| id == &request.finding_id)
        || request
            .snapshot
            .candidate_ids
            .iter()
            .any(|id| id == &request.finding_id);
    if !owned {
        return ReviewPatchActionResponse::err(
            "finding_not_owned",
            &format!(
                "finding_id '{}' does not belong to session_id '{}'",
                request.finding_id, request.session_id
            ),
        );
    }

    let patch = request
        .snapshot
        .patches
        .iter()
        .find(|patch| patch.finding_id == request.finding_id);
    let finding = request
        .snapshot
        .findings
        .iter()
        .find(|finding| finding.id == request.finding_id);

    match request.operation.as_str() {
        "queue_context" => queue_context(&request.action, patch, finding),
        "plan_execution" => execution_plan(&request.action, patch, finding),
        _ => ReviewPatchActionResponse::err("unsupported_operation", "unsupported patch operation"),
    }
}

fn queue_context(
    action: &str,
    patch: Option<&ReviewPatchRecord>,
    finding: Option<&ReviewFindingRecord>,
) -> ReviewPatchActionResponse {
    match action {
        "apply_patch" => {
            let Some(patch) = patch else {
                return ReviewPatchActionResponse::err(
                    "missing_prepared_patch",
                    "no prepared patch artifact found. Run review_prepare_patch first.",
                );
            };
            if patch.verify_status != "verified" {
                return ReviewPatchActionResponse::err(
                    "patch_not_verified",
                    "patch artifact is not verified. Run review_prepare_patch or review_verify_patch first.",
                );
            }
        }
        "close_finding" => {
            let Some(finding) = finding else {
                return ReviewPatchActionResponse::err(
                    "finding_not_owned",
                    "finding is not available in the snapshot",
                );
            };
            if !can_close(finding, patch) {
                return ReviewPatchActionResponse::err(
                    "finding_not_closable",
                    "finding cannot be closed until it is merged, dismissed, or validated after apply.",
                );
            }
        }
        _ => {}
    }
    ReviewPatchActionResponse::ok(Vec::new(), patch, finding)
}

fn execution_plan(
    action: &str,
    patch: Option<&ReviewPatchRecord>,
    finding: Option<&ReviewFindingRecord>,
) -> ReviewPatchActionResponse {
    let steps = match action {
        "prepare_patch" => vec!["prepare_patch".to_string()],
        "verify_patch" => {
            if patch.is_none() {
                return ReviewPatchActionResponse::err(
                    "invalid_patch",
                    "patch artifact missing for verification",
                );
            }
            vec!["verify_patch".to_string()]
        }
        "apply_patch" | "apply_fix" => match patch {
            None => vec!["prepare_patch".to_string(), "apply_patch".to_string()],
            Some(patch) if patch.verify_status != "verified" => {
                vec!["verify_patch".to_string(), "apply_patch".to_string()]
            }
            Some(_) => vec!["apply_patch".to_string()],
        },
        "revalidate_finding" | "rollback_patch" | "open_pr" | "merge_pr" | "resolve_conflicts" => {
            if patch.is_none() {
                return ReviewPatchActionResponse::err(
                    "invalid_patch",
                    "patch artifact missing for requested action",
                );
            }
            vec![action.to_string()]
        }
        "close_finding" => {
            let Some(finding) = finding else {
                return ReviewPatchActionResponse::err(
                    "finding_not_owned",
                    "finding is not available in the snapshot",
                );
            };
            if !can_close(finding, patch) {
                return ReviewPatchActionResponse::err(
                    "finding_not_closable",
                    "finding cannot be closed until it is merged, dismissed, or validated after apply.",
                );
            }
            vec!["close_finding".to_string()]
        }
        _ => {
            return ReviewPatchActionResponse::err("unsupported_action", "unsupported patch action")
        }
    };
    ReviewPatchActionResponse::ok(steps, patch, finding)
}

fn can_close(finding: &ReviewFindingRecord, patch: Option<&ReviewPatchRecord>) -> bool {
    match finding.status.as_str() {
        "merged" | "dismissed" | "wont_fix" | "closed" => true,
        "patch_applied" | "fix_applied" => {
            let Some(patch) = patch else { return false };
            if let Some(patch_artifact_id) = finding.patch_artifact_id.as_ref() {
                if patch.id != *patch_artifact_id {
                    return false;
                }
            }
            matches!(patch.status.as_str(), "applied" | "merged")
                && patch.validation_status == "passed"
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_patch::models::{ReviewPatchActionRequest, ReviewPatchSnapshot};

    #[test]
    fn queue_context_rejects_unverified_apply_patch() {
        let response = handle_patch_action(ReviewPatchActionRequest {
            schema_version: 1,
            operation: "queue_context".to_string(),
            action: "apply_patch".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: ReviewPatchSnapshot {
                session_id: "s1".to_string(),
                conversation_id: None,
                finding_ids: vec!["f1".to_string()],
                candidate_ids: Vec::new(),
                patches: vec![ReviewPatchRecord {
                    id: "p1".to_string(),
                    finding_id: "f1".to_string(),
                    status: "draft".to_string(),
                    verify_status: "pending".to_string(),
                    validation_status: "pending".to_string(),
                    risk_score: 0.2,
                }],
                findings: Vec::new(),
            },
        });
        assert!(response.is_error);
    }

    #[test]
    fn execution_plan_infers_prepare_then_apply_when_patch_missing() {
        let response = handle_patch_action(ReviewPatchActionRequest {
            schema_version: 1,
            operation: "plan_execution".to_string(),
            action: "apply_fix".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: ReviewPatchSnapshot {
                session_id: "s1".to_string(),
                conversation_id: None,
                finding_ids: vec!["f1".to_string()],
                candidate_ids: Vec::new(),
                patches: Vec::new(),
                findings: vec![ReviewFindingRecord {
                    id: "f1".to_string(),
                    status: "open".to_string(),
                    severity: "warning".to_string(),
                    category: "correctness".to_string(),
                    message: "m".to_string(),
                    patch_artifact_id: None,
                }],
            },
        });
        assert_eq!(
            response.steps,
            vec!["prepare_patch".to_string(), "apply_patch".to_string()]
        );
    }

    #[test]
    fn queue_context_rejects_close_when_validation_missing() {
        let response = handle_patch_action(ReviewPatchActionRequest {
            schema_version: 1,
            operation: "queue_context".to_string(),
            action: "close_finding".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: ReviewPatchSnapshot {
                session_id: "s1".to_string(),
                conversation_id: None,
                finding_ids: vec!["f1".to_string()],
                candidate_ids: Vec::new(),
                patches: vec![ReviewPatchRecord {
                    id: "p1".to_string(),
                    finding_id: "f1".to_string(),
                    status: "applied".to_string(),
                    verify_status: "verified".to_string(),
                    validation_status: "failed".to_string(),
                    risk_score: 0.2,
                }],
                findings: vec![ReviewFindingRecord {
                    id: "f1".to_string(),
                    status: "patch_applied".to_string(),
                    severity: "warning".to_string(),
                    category: "correctness".to_string(),
                    message: "m".to_string(),
                    patch_artifact_id: Some("p1".to_string()),
                }],
            },
        });
        assert!(response.is_error);
    }

    #[test]
    fn execution_plan_allows_close_when_merged() {
        let response = handle_patch_action(ReviewPatchActionRequest {
            schema_version: 1,
            operation: "plan_execution".to_string(),
            action: "close_finding".to_string(),
            session_id: "s1".to_string(),
            finding_id: "f1".to_string(),
            conversation_id: None,
            snapshot: ReviewPatchSnapshot {
                session_id: "s1".to_string(),
                conversation_id: None,
                finding_ids: vec!["f1".to_string()],
                candidate_ids: Vec::new(),
                patches: Vec::new(),
                findings: vec![ReviewFindingRecord {
                    id: "f1".to_string(),
                    status: "merged".to_string(),
                    severity: "warning".to_string(),
                    category: "correctness".to_string(),
                    message: "m".to_string(),
                    patch_artifact_id: None,
                }],
            },
        });
        assert_eq!(response.steps, vec!["close_finding".to_string()]);
    }
}
