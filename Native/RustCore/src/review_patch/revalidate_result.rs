use super::models::{ReviewPatchRevalidateResultRequest, ReviewPatchRevalidateResultResponse};

pub fn build_revalidate_result(
    request: ReviewPatchRevalidateResultRequest,
) -> ReviewPatchRevalidateResultResponse {
    let validation_status = request
        .validation_status
        .as_deref()
        .unwrap_or("pending")
        .trim()
        .to_string();
    let status = if validation_status == "passed" {
        "applied".to_string()
    } else {
        "apply_failed".to_string()
    };

    ReviewPatchRevalidateResultResponse::success(
        status,
        request.validation_run_id,
        validation_status,
        request.validation_summary.clone(),
        request.validation_summary,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_revalidate_result_marks_applied_on_pass() {
        let response = build_revalidate_result(ReviewPatchRevalidateResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            validation_run_id: Some("run-1".to_string()),
            validation_status: Some("passed".to_string()),
            validation_summary: Some("all good".to_string()),
        });
        assert_eq!(response.status.as_deref(), Some("applied"));
    }

    #[test]
    fn build_revalidate_result_marks_apply_failed_on_failed_validation() {
        let response = build_revalidate_result(ReviewPatchRevalidateResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            validation_run_id: Some("run-1".to_string()),
            validation_status: Some("failed".to_string()),
            validation_summary: Some("tests failed".to_string()),
        });
        assert_eq!(response.status.as_deref(), Some("apply_failed"));
    }
}
