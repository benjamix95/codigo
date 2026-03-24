use super::models::{
    ReviewPatchRollbackExecutionContextRequest, ReviewPatchRollbackExecutionContextResponse,
};

pub fn build_rollback_execution_context(
    request: ReviewPatchRollbackExecutionContextRequest,
) -> ReviewPatchRollbackExecutionContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchRollbackExecutionContextResponse::error("schemaVersion must be 1");
    }
    if request.status != "applied" {
        return ReviewPatchRollbackExecutionContextResponse::error(
            "Rollback non disponibile per questa patch.",
        );
    }
    if request
        .rollback_ref
        .as_ref()
        .is_none_or(|value| value.trim().is_empty())
    {
        return ReviewPatchRollbackExecutionContextResponse::error(
            "Rollback non disponibile per questa patch.",
        );
    }

    ReviewPatchRollbackExecutionContextResponse::success(format!("{}-rollback", request.patch_id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_rollback_execution_context_requires_applied_status_and_ref() {
        let response =
            build_rollback_execution_context(ReviewPatchRollbackExecutionContextRequest {
                schema_version: 1,
                patch_id: "patch-1".to_string(),
                status: "verified".to_string(),
                rollback_ref: None,
            });

        assert!(response.is_error);
    }

    #[test]
    fn build_rollback_execution_context_derives_patch_prefix() {
        let response =
            build_rollback_execution_context(ReviewPatchRollbackExecutionContextRequest {
                schema_version: 1,
                patch_id: "patch-1".to_string(),
                status: "applied".to_string(),
                rollback_ref: Some("reverse:patch-1".to_string()),
            });

        assert_eq!(
            response.patch_file_prefix.as_deref(),
            Some("patch-1-rollback")
        );
    }
}
