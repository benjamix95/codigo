use super::models::{ReviewPatchApplyResultRequest, ReviewPatchApplyResultResponse};

pub fn build_apply_result(
    request: ReviewPatchApplyResultRequest,
) -> ReviewPatchApplyResultResponse {
    if !request.success {
        return ReviewPatchApplyResultResponse::error(
            request
                .error_message
                .unwrap_or_else(|| "patch apply failed".to_string()),
        );
    }

    let validation_status = request
        .validation_status
        .as_deref()
        .unwrap_or("pending")
        .trim()
        .to_string();
    if validation_status != "passed" {
        return ReviewPatchApplyResultResponse::error(
            request
                .validation_summary
                .unwrap_or_else(|| "validation failed".to_string()),
        );
    }

    ReviewPatchApplyResultResponse::success(
        "applied".to_string(),
        "verified".to_string(),
        format!("reverse:{}", request.patch_id),
        request.validation_run_id,
        "passed".to_string(),
        request.validation_summary,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_apply_result_marks_applied_on_success() {
        let response = build_apply_result(ReviewPatchApplyResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            finding_id: "finding-1".to_string(),
            success: true,
            validation_run_id: Some("run-1".to_string()),
            validation_status: Some("passed".to_string()),
            validation_summary: Some("all good".to_string()),
            error_message: None,
        });

        assert!(!response.is_error);
        assert_eq!(response.status.as_deref(), Some("applied"));
        assert_eq!(response.rollback_ref.as_deref(), Some("reverse:patch-1"));
        assert_eq!(response.validation_status.as_deref(), Some("passed"));
    }

    #[test]
    fn build_apply_result_errors_when_validation_failed() {
        let response = build_apply_result(ReviewPatchApplyResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            finding_id: "finding-1".to_string(),
            success: true,
            validation_run_id: Some("run-1".to_string()),
            validation_status: Some("failed".to_string()),
            validation_summary: Some("tests failed".to_string()),
            error_message: None,
        });

        assert!(response.is_error);
    }
}
