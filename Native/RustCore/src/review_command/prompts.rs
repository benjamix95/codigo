use super::config::parse_bool;
use super::models::{ReviewCommandPromptRequest, ReviewCommandPromptResponse};

pub fn build_start_prompt(request: ReviewCommandPromptRequest) -> ReviewCommandPromptResponse {
    let override_prompt = request
        .payload
        .get("review_prompt_override")
        .or_else(|| request.payload.get("bughunter_prompt_override"))
        .map(|value| value.trim())
        .filter(|value| !value.is_empty());
    if let Some(override_prompt) = override_prompt {
        return ReviewCommandPromptResponse::success(override_prompt);
    }

    let scope = request
        .payload
        .get("scope")
        .map(|value| value.trim().to_lowercase())
        .unwrap_or_else(|| "uncommitted".to_string());
    match scope.as_str() {
        "staged" => ReviewCommandPromptResponse::success(format!(
            "[REVIEW_SCOPE:staged] Start a structured code review session {}.\nFocus on actionable findings and pipeline-safe fixes.",
            request.session_id
        )),
        "against_ref" => {
            let reference = request
                .payload
                .get("ref")
                .map(|value| value.trim())
                .filter(|value| !value.is_empty())
                .unwrap_or("HEAD~1");
            let analysis_only = request
                .payload
                .get("analysis_only")
                .and_then(|value| parse_bool(value))
                .unwrap_or(request.config.analysis_only);
            let max_rounds = request
                .payload
                .get("max_rounds")
                .and_then(|value| value.trim().parse::<i32>().ok())
                .unwrap_or(request.config.max_rounds);
            let autofix_enabled = if analysis_only { "false" } else { "true" };
            ReviewCommandPromptResponse::success(format!(
                "[AGAINST:{reference}] [REVIEW_AUTOFIX:{autofix_enabled}] [REVIEW_MAX_ROUNDS:{max_rounds}]\nRun a structured code review against {reference}. Focus on actionable findings and pipeline-safe fixes."
            ))
        }
        _ => ReviewCommandPromptResponse::success(format!(
            "[REVIEW_SCOPE:uncommitted] Start a structured code review session {}.\nFocus on actionable findings and pipeline-safe fixes.",
            request.session_id
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_command::models::ReviewCommandConfig;
    use std::collections::HashMap;

    fn default_config() -> ReviewCommandConfig {
        ReviewCommandConfig {
            max_workers: 4,
            max_rounds: 3,
            analysis_backend: "codex".to_string(),
            execution_backend: "codex".to_string(),
            analysis_only: false,
        }
    }

    #[test]
    fn staged_prompt_uses_staged_scope() {
        let response = build_start_prompt(ReviewCommandPromptRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            payload: HashMap::from([("scope".to_string(), "staged".to_string())]),
            config: default_config(),
        });
        assert!(!response.is_error);
        assert!(response
            .prompt
            .as_deref()
            .unwrap_or_default()
            .contains("[REVIEW_SCOPE:staged]"));
    }

    #[test]
    fn against_ref_prompt_includes_reference_and_rounds() {
        let response = build_start_prompt(ReviewCommandPromptRequest {
            schema_version: 1,
            session_id: "session-2".to_string(),
            payload: HashMap::from([
                ("scope".to_string(), "against_ref".to_string()),
                ("ref".to_string(), "main".to_string()),
                ("max_rounds".to_string(), "5".to_string()),
            ]),
            config: default_config(),
        });
        let prompt = response.prompt.as_deref().unwrap_or_default();
        assert!(prompt.contains("[AGAINST:main]"));
        assert!(prompt.contains("[REVIEW_MAX_ROUNDS:5]"));
    }

    #[test]
    fn explicit_override_wins() {
        let response = build_start_prompt(ReviewCommandPromptRequest {
            schema_version: 1,
            session_id: "session-3".to_string(),
            payload: HashMap::from([(
                "review_prompt_override".to_string(),
                "custom start prompt".to_string(),
            )]),
            config: default_config(),
        });
        assert_eq!(response.prompt.as_deref(), Some("custom start prompt"));
    }
}
