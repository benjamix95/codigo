use super::models::{ReviewPatchRollbackResultRequest, ReviewPatchRollbackResultResponse};

pub fn build_rollback_result(
    request: ReviewPatchRollbackResultRequest,
) -> ReviewPatchRollbackResultResponse {
    if !request.success {
        return ReviewPatchRollbackResultResponse::error(
            request
                .error_message
                .unwrap_or_else(|| "rollback failed".to_string()),
        );
    }

    ReviewPatchRollbackResultResponse::success(
        "rolled_back".to_string(),
        "Rollback applied successfully".to_string(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_rollback_result_marks_rolled_back_on_success() {
        let response = build_rollback_result(ReviewPatchRollbackResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            success: true,
            error_message: None,
        });
        assert_eq!(response.status.as_deref(), Some("rolled_back"));
    }

    #[test]
    fn build_rollback_result_errors_on_failure() {
        let response = build_rollback_result(ReviewPatchRollbackResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            success: false,
            error_message: Some("boom".to_string()),
        });
        assert!(response.is_error);
    }
}
