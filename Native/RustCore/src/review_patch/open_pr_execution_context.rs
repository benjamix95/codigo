use super::pr_result_models::{
    ReviewPatchOpenPrExecutionContextRequest, ReviewPatchOpenPrExecutionContextResponse,
};

pub fn build_open_pr_execution_context(
    request: ReviewPatchOpenPrExecutionContextRequest,
) -> ReviewPatchOpenPrExecutionContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchOpenPrExecutionContextResponse::error("schemaVersion must be 1");
    }

    let base_branch_name = request
        .artifact_base_branch_name
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(request.current_branch_name);
    let branch_name = request
        .existing_branch_name
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| {
            format!(
                "codex/review-pr-{}",
                request.finding_id.chars().take(8).collect::<String>().to_lowercase()
            )
        });
    let worktree_path = format!(
        "{}/{}",
        request.worktree_root.trim_end_matches('/'),
        branch_name.replace('/', "-")
    );

    ReviewPatchOpenPrExecutionContextResponse::success(
        branch_name,
        base_branch_name,
        worktree_path,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_open_pr_execution_context_uses_existing_values_when_available() {
        let response = build_open_pr_execution_context(ReviewPatchOpenPrExecutionContextRequest {
            schema_version: 1,
            finding_id: "finding-12345678".to_string(),
            artifact_base_branch_name: Some("release".to_string()),
            current_branch_name: "main".to_string(),
            existing_branch_name: Some("codex/review-pr-custom".to_string()),
            worktree_root: "/tmp/codigo-review-prs".to_string(),
        });

        assert_eq!(
            response.branch_name.as_deref(),
            Some("codex/review-pr-custom")
        );
        assert_eq!(response.base_branch_name.as_deref(), Some("release"));
        assert_eq!(
            response.worktree_path.as_deref(),
            Some("/tmp/codigo-review-prs/codex-review-pr-custom")
        );
    }
}
