use super::pr_result_models::{ReviewPatchMergeResultRequest, ReviewPatchMergeResultResponse};

pub fn build_merge_result(
    request: ReviewPatchMergeResultRequest,
) -> ReviewPatchMergeResultResponse {
    if !request.success {
        return ReviewPatchMergeResultResponse::error(
            request
                .error_message
                .unwrap_or_else(|| "merge failed".to_string()),
        );
    }

    ReviewPatchMergeResultResponse::success(
        "merged".to_string(),
        "merged".to_string(),
        request.pr_url,
        Vec::new(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_merge_result_marks_patch_merged() {
        let response = build_merge_result(ReviewPatchMergeResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            pr_url: Some("https://example.test/pr/1".to_string()),
            success: true,
            error_message: None,
        });
        assert_eq!(response.status.as_deref(), Some("merged"));
        assert_eq!(response.merge_status.as_deref(), Some("merged"));
    }

    #[test]
    fn build_merge_result_errors_on_failure() {
        let response = build_merge_result(ReviewPatchMergeResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            pr_url: None,
            success: false,
            error_message: Some("boom".to_string()),
        });
        assert!(response.is_error);
    }
}
