use super::pr_result_models::{
    ReviewPatchResolveConflictsResultRequest, ReviewPatchResolveConflictsResultResponse,
};

pub fn build_resolve_conflicts_result(
    _request: ReviewPatchResolveConflictsResultRequest,
) -> ReviewPatchResolveConflictsResultResponse {
    ReviewPatchResolveConflictsResultResponse::success(
        "verified".to_string(),
        "pending".to_string(),
        Vec::new(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_resolve_conflicts_result_clears_conflicts_and_marks_pending_merge() {
        let response =
            build_resolve_conflicts_result(ReviewPatchResolveConflictsResultRequest {
                schema_version: 1,
                patch_id: "patch-1".to_string(),
            });
        assert_eq!(response.status.as_deref(), Some("verified"));
        assert_eq!(response.merge_status.as_deref(), Some("pending"));
        assert_eq!(response.conflicts.as_ref().map(Vec::len), Some(0));
    }
}
