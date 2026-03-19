use super::models::{ReviewPatchVerifyResultRequest, ReviewPatchVerifyResultResponse};

pub fn build_verify_result(
    request: ReviewPatchVerifyResultRequest,
) -> ReviewPatchVerifyResultResponse {
    if request.success {
        return ReviewPatchVerifyResultResponse::success(
            "verified".to_string(),
            "verified".to_string(),
            Vec::new(),
            None,
        );
    }

    let message = request
        .error_message
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "patch verification failed".to_string());

    ReviewPatchVerifyResultResponse::success(
        "conflict".to_string(),
        "failed".to_string(),
        vec![message.clone()],
        Some(message),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_verify_result_marks_verified_on_success() {
        let response = build_verify_result(ReviewPatchVerifyResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            finding_id: "finding-1".to_string(),
            success: true,
            error_message: None,
        });

        assert!(!response.is_error);
        assert_eq!(response.status.as_deref(), Some("verified"));
        assert_eq!(response.verify_status.as_deref(), Some("verified"));
        assert!(response.conflicts.unwrap().is_empty());
    }

    #[test]
    fn build_verify_result_marks_conflict_on_failure() {
        let response = build_verify_result(ReviewPatchVerifyResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            finding_id: "finding-1".to_string(),
            success: false,
            error_message: Some("cannot apply cleanly".to_string()),
        });

        assert!(!response.is_error);
        assert_eq!(response.status.as_deref(), Some("conflict"));
        assert_eq!(response.verify_status.as_deref(), Some("failed"));
        assert_eq!(response.apply_message.as_deref(), Some("cannot apply cleanly"));
    }
}
