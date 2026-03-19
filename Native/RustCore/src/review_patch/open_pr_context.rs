use super::pr_result_models::{
    ReviewPatchOpenPrContextRequest, ReviewPatchOpenPrContextResponse,
};

pub fn build_open_pr_context(
    request: ReviewPatchOpenPrContextRequest,
) -> ReviewPatchOpenPrContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchOpenPrContextResponse::error("schemaVersion must be 1");
    }
    let fallback_name = request
        .file_path
        .rsplit('/')
        .next()
        .filter(|value| !value.is_empty())
        .unwrap_or(&request.file_path);
    let title = format!("fix(review): {}", fallback_name);
    let body = format!(
        "{}\n\n{}",
        request.message,
        request
            .verification_report
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "Verification unavailable".to_string())
    );
    ReviewPatchOpenPrContextResponse::success(title, body)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_open_pr_context_uses_file_tail_and_verification_fallback() {
        let response = build_open_pr_context(ReviewPatchOpenPrContextRequest {
            schema_version: 1,
            file_path: "Sources/Authz.swift".to_string(),
            message: "Auth issue".to_string(),
            verification_report: Some("verified".to_string()),
        });
        assert_eq!(response.title.as_deref(), Some("fix(review): Authz.swift"));
        assert_eq!(response.body.as_deref(), Some("Auth issue\n\nverified"));
    }
}
