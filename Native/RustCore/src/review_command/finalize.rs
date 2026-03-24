use super::models::{ReviewDeferredCommandFinalizeRequest, ReviewDeferredCommandFinalizeResponse};

pub fn finalize_deferred_command(
    request: ReviewDeferredCommandFinalizeRequest,
) -> ReviewDeferredCommandFinalizeResponse {
    if request.phase == "completed" {
        if !request.auto_prepare_succeeded {
            return ReviewDeferredCommandFinalizeResponse::success(
                "failed",
                "Code review completed, but automatic patch preview preparation failed",
            );
        }
        if !request.source_state_succeeded {
            return ReviewDeferredCommandFinalizeResponse::success(
                "failed",
                "Code review completed, but the source finding state could not be updated",
            );
        }
        return ReviewDeferredCommandFinalizeResponse::success(
            "completed",
            format!("Code review session {} completed", request.session_id),
        );
    }

    ReviewDeferredCommandFinalizeResponse::success(
        "failed",
        request.last_error.unwrap_or_else(|| {
            format!(
                "Code review session {} did not complete successfully",
                request.session_id
            )
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn completes_when_phase_and_side_effects_are_clean() {
        let response = finalize_deferred_command(ReviewDeferredCommandFinalizeRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            phase: "completed".to_string(),
            last_error: None,
            auto_prepare_succeeded: true,
            source_state_succeeded: true,
        });
        assert_eq!(response.command_status, "completed");
    }

    #[test]
    fn fails_when_auto_prepare_fails() {
        let response = finalize_deferred_command(ReviewDeferredCommandFinalizeRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            phase: "completed".to_string(),
            last_error: None,
            auto_prepare_succeeded: false,
            source_state_succeeded: true,
        });
        assert_eq!(response.command_status, "failed");
    }
}
