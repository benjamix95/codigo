use super::pr_result_models::{ReviewPatchOpenPrResultRequest, ReviewPatchOpenPrResultResponse};

pub fn build_open_pr_result(
    request: ReviewPatchOpenPrResultRequest,
) -> ReviewPatchOpenPrResultResponse {
    ReviewPatchOpenPrResultResponse::success(
        "pr_opened".to_string(),
        "opened".to_string(),
        request.branch_name,
        request.base_branch_name,
        request.worktree_path,
        request.pr_url,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_open_pr_result_marks_pr_opened() {
        let response = build_open_pr_result(ReviewPatchOpenPrResultRequest {
            schema_version: 1,
            patch_id: "patch-1".to_string(),
            branch_name: "codex/review-pr-123".to_string(),
            base_branch_name: "main".to_string(),
            worktree_path: "/tmp/worktree".to_string(),
            pr_url: "https://example.test/pr/1".to_string(),
        });
        assert_eq!(response.status.as_deref(), Some("pr_opened"));
        assert_eq!(response.pr_status.as_deref(), Some("opened"));
    }
}
