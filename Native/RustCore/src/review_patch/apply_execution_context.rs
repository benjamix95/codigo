use super::models::{
    ReviewPatchApplyExecutionContextRequest, ReviewPatchApplyExecutionContextResponse,
};

pub fn build_apply_execution_context(
    request: ReviewPatchApplyExecutionContextRequest,
) -> ReviewPatchApplyExecutionContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchApplyExecutionContextResponse::error("schemaVersion must be 1");
    }
    if request.verify_status != "verified" {
        return ReviewPatchApplyExecutionContextResponse::error(
            "La patch non è stata verificata con successo e non può essere applicata.",
        );
    }

    ReviewPatchApplyExecutionContextResponse::success(request.patch_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_apply_execution_context_requires_verified_status() {
        let response = build_apply_execution_context(ReviewPatchApplyExecutionContextRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            verify_status: "pending".to_string(),
        });

        assert!(response.is_error);
    }

    #[test]
    fn build_apply_execution_context_derives_prefix_and_validation_context() {
        let response = build_apply_execution_context(ReviewPatchApplyExecutionContextRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            verify_status: "verified".to_string(),
        });

        assert_eq!(response.patch_file_prefix.as_deref(), Some("patch-1"));
        assert_eq!(response.validation_trigger.as_deref(), Some("review_patch_apply"));
        assert_eq!(response.workspace_contains_patch, Some(true));
    }
}
