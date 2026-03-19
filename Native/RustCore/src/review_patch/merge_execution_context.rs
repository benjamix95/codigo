use super::pr_result_models::{
    ReviewPatchMergeExecutionContextRequest, ReviewPatchMergeExecutionContextResponse,
};

pub fn build_merge_execution_context(
    request: ReviewPatchMergeExecutionContextRequest,
) -> ReviewPatchMergeExecutionContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchMergeExecutionContextResponse::error("schemaVersion must be 1");
    }

    let pr_url = match request.pr_url.filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => {
            return ReviewPatchMergeExecutionContextResponse::error(
                "PR non presente sull'artefatto patch.",
            )
        }
    };

    ReviewPatchMergeExecutionContextResponse::success(
        pr_url,
        request.safe_only,
        request.safe_only,
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_merge_execution_context_requires_pr_url() {
        let response = build_merge_execution_context(ReviewPatchMergeExecutionContextRequest {
            schema_version: 1,
            pr_url: None,
            safe_only: true,
        });

        assert!(response.is_error);
    }

    #[test]
    fn build_merge_execution_context_uses_safe_only_for_retry_plan() {
        let response = build_merge_execution_context(ReviewPatchMergeExecutionContextRequest {
            schema_version: 1,
            pr_url: Some("https://example.test/pr/1".to_string()),
            safe_only: true,
        });

        assert_eq!(response.pr_url.as_deref(), Some("https://example.test/pr/1"));
        assert_eq!(response.first_merge_auto, Some(true));
        assert_eq!(response.retry_after_conflicts, Some(true));
        assert_eq!(response.retry_merge_auto, Some(false));
    }
}
