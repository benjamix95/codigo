use super::models::{ReviewPatchPrepareResultRequest, ReviewPatchPrepareResultResponse};

pub fn build_prepare_result(
    request: ReviewPatchPrepareResultRequest,
) -> ReviewPatchPrepareResultResponse {
    if request.schema_version != 1 {
        return ReviewPatchPrepareResultResponse::error("schemaVersion must be 1");
    }

    let changed_lines = request
        .patch_text
        .lines()
        .filter(|line| {
            (line.starts_with('+') || line.starts_with('-'))
                && !line.starts_with("+++")
                && !line.starts_with("---")
        })
        .count();
    let files_changed_score = (request.touched_files.len() as f64 / 20.0).min(1.0);
    let lines_changed_score = (changed_lines as f64 / 500.0).min(1.0);
    let risk_score = (files_changed_score * 0.15) + (lines_changed_score * 0.20) + (0.3 * 0.15);
    let diff_preview = request.patch_text.chars().take(12_000).collect::<String>();

    ReviewPatchPrepareResultResponse::success(
        diff_preview,
        risk_score,
        request.base_branch_name,
        request
            .verification_report
            .filter(|value| !value.trim().is_empty()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_prepare_result_derives_preview_and_risk_score() {
        let response = build_prepare_result(ReviewPatchPrepareResultRequest {
            schema_version: 1,
            finding_id: "finding-1".to_string(),
            patch_text: "diff --git a/File.swift b/File.swift\n@@\n-old\n+new\n".to_string(),
            touched_files: vec!["File.swift".to_string()],
            base_branch_name: "main".to_string(),
            verification_report: Some("verified".to_string()),
        });

        assert!(!response.is_error);
        assert_eq!(response.status.as_deref(), Some("draft"));
        assert_eq!(response.verify_status.as_deref(), Some("pending"));
        assert_eq!(response.pr_status.as_deref(), Some("not_requested"));
        assert_eq!(response.merge_status.as_deref(), Some("not_requested"));
        assert_eq!(response.base_branch_name.as_deref(), Some("main"));
        assert_eq!(response.verification_report.as_deref(), Some("verified"));
        assert_eq!(
            response.diff_preview.as_deref(),
            Some("diff --git a/File.swift b/File.swift\n@@\n-old\n+new\n")
        );
        assert_eq!(response.risk_score, Some(0.0533));
    }
}
