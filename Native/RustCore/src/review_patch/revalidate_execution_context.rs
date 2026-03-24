use super::models::{
    ReviewPatchRevalidateExecutionContextRequest, ReviewPatchRevalidateExecutionContextResponse,
};

pub fn build_revalidate_execution_context(
    request: ReviewPatchRevalidateExecutionContextRequest,
) -> ReviewPatchRevalidateExecutionContextResponse {
    if request.schema_version != 1 {
        return ReviewPatchRevalidateExecutionContextResponse::error("schemaVersion must be 1");
    }
    if request.status != "applied" {
        return ReviewPatchRevalidateExecutionContextResponse::error(
            "La patch non risulta applicata nel workspace corrente.",
        );
    }
    ReviewPatchRevalidateExecutionContextResponse::success()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_revalidate_execution_context_requires_applied_status() {
        let response =
            build_revalidate_execution_context(ReviewPatchRevalidateExecutionContextRequest {
                schema_version: 1,
                status: "verified".to_string(),
            });

        assert!(response.is_error);
    }
}
