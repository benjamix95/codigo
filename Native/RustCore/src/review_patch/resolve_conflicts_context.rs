use super::pr_result_models::{
    ReviewPatchResolveConflictsContextRequest, ReviewPatchResolveConflictsContextResponse,
};

pub fn build_resolve_conflicts_context(
    request: ReviewPatchResolveConflictsContextRequest,
) -> ReviewPatchResolveConflictsContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchResolveConflictsContextResponse::error("schemaVersion must be 1");
    }

    let worktree_path = match request.worktree_path.filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => {
            return ReviewPatchResolveConflictsContextResponse::error(
                "Worktree o branch mancanti per la risoluzione conflitti.",
            )
        }
    };
    let branch_name = match request.branch_name.filter(|value| !value.trim().is_empty()) {
        Some(value) => value,
        None => {
            return ReviewPatchResolveConflictsContextResponse::error(
                "Worktree o branch mancanti per la risoluzione conflitti.",
            )
        }
    };
    let base_branch_name =
        match request.base_branch_name.filter(|value| !value.trim().is_empty()) {
            Some(value) => value,
            None => {
                return ReviewPatchResolveConflictsContextResponse::error(
                    "Worktree o branch mancanti per la risoluzione conflitti.",
                )
            }
        };
    let commit_message = format!(
        "chore(review): sync {} with {}",
        branch_name, base_branch_name
    );

    ReviewPatchResolveConflictsContextResponse::success(
        worktree_path,
        branch_name,
        base_branch_name,
        commit_message,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_resolve_conflicts_context_requires_full_context() {
        let response = build_resolve_conflicts_context(ReviewPatchResolveConflictsContextRequest {
            schema_version: 1,
            worktree_path: None,
            branch_name: Some("feature".to_string()),
            base_branch_name: Some("main".to_string()),
        });

        assert!(response.is_error);
    }

    #[test]
    fn build_resolve_conflicts_context_emits_commit_message() {
        let response = build_resolve_conflicts_context(ReviewPatchResolveConflictsContextRequest {
            schema_version: 1,
            worktree_path: Some("/tmp/worktree".to_string()),
            branch_name: Some("feature".to_string()),
            base_branch_name: Some("main".to_string()),
        });

        assert_eq!(response.worktree_path.as_deref(), Some("/tmp/worktree"));
        assert_eq!(response.branch_name.as_deref(), Some("feature"));
        assert_eq!(response.base_branch_name.as_deref(), Some("main"));
        assert_eq!(
            response.commit_message.as_deref(),
            Some("chore(review): sync feature with main")
        );
    }
}
