use super::models::ReviewTask;
use super::scope::{
    infer_review_scope_optional, is_valid_against_ref_format, normalized_against_ref_input,
    normalized_against_ref_revision, parse_against_ref, parse_review_scope,
};
use super::tasks::{
    classify_review_outcome, extract_review_tasks_json, parse_review_tasks, parse_tasks_json,
    ExtractedReviewTasks, ParsedTasksResult, ReviewFindingsState, TaskExtraction,
};
use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewProviderPlanRequest {
    pub schema_version: i32,
    pub operation: String,
    pub prompt: Option<String>,
    pub text: Option<String>,
    #[serde(default)]
    pub allowed_files: Vec<String>,
    pub max_workers: Option<i32>,
    pub against_ref: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewProviderReduceRequest {
    pub schema_version: i32,
    pub operation: String,
    pub text: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewProviderPlanResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub clean_prompt: Option<String>,
    pub explicit_scope: Option<String>,
    pub inferred_scope: Option<String>,
    pub against_ref: Option<String>,
    pub is_valid_against_ref: Option<bool>,
    pub normalized_against_ref_input: Option<String>,
    pub normalized_against_ref_revision: Option<String>,
    pub extraction_kind: Option<String>,
    pub tasks: Option<Vec<ReviewTask>>,
    pub reason: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewProviderReduceResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub findings_state: Option<String>,
    pub reason: Option<String>,
}

impl ReviewProviderPlanResponse {
    fn success() -> Self {
        Self {
            schema_version: 1,
            error: None,
            clean_prompt: None,
            explicit_scope: None,
            inferred_scope: None,
            against_ref: None,
            is_valid_against_ref: None,
            normalized_against_ref_input: None,
            normalized_against_ref_revision: None,
            extraction_kind: None,
            tasks: None,
            reason: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        let mut response = Self::success();
        response.error = Some(ReviewCoreErrorPayload::new(code, message));
        response
    }
}

impl ReviewProviderReduceResponse {
    fn success() -> Self {
        Self {
            schema_version: 1,
            error: None,
            findings_state: None,
            reason: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        let mut response = Self::success();
        response.error = Some(ReviewCoreErrorPayload::new(code, message));
        response
    }
}

pub fn plan_step(request: ReviewProviderPlanRequest) -> ReviewProviderPlanResponse {
    if request.schema_version != 1 {
        return ReviewProviderPlanResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    match request.operation.as_str() {
        "parse_prompt" => {
            let prompt = request.prompt.unwrap_or_default();
            let (without_scope, explicit_scope) = parse_review_scope(&prompt);
            let (clean_prompt, against_ref) = parse_against_ref(&without_scope);
            let inferred_scope = if explicit_scope.is_none() {
                infer_review_scope_optional(&clean_prompt)
            } else {
                None
            };
            let mut response = ReviewProviderPlanResponse::success();
            response.clean_prompt = Some(clean_prompt);
            response.explicit_scope = explicit_scope;
            response.inferred_scope = inferred_scope;
            response.against_ref = against_ref;
            response
        }
        "validate_against_ref" => {
            let reference = request.against_ref.unwrap_or_default();
            let mut response = ReviewProviderPlanResponse::success();
            response.is_valid_against_ref = Some(is_valid_against_ref_format(&reference));
            response
        }
        "normalize_against_ref" => {
            let reference = request.against_ref.unwrap_or_default();
            let mut response = ReviewProviderPlanResponse::success();
            response.normalized_against_ref_input = Some(normalized_against_ref_input(&reference));
            response.normalized_against_ref_revision = Some(normalized_against_ref_revision(&reference));
            response
        }
        "parse_tasks_json" => {
            let json = request.text.unwrap_or_default();
            extraction_response_from_parsed(parse_tasks_json(&json, &request.allowed_files))
        }
        "extract_review_tasks_json" => {
            let text = request.text.unwrap_or_default();
            match extract_review_tasks_json(&text, &request.allowed_files) {
                Some(ExtractedReviewTasks::JsonTasks(tasks)) => {
                    let mut response = ReviewProviderPlanResponse::success();
                    response.extraction_kind = Some("json_tasks".to_string());
                    response.tasks = Some(tasks);
                    response
                }
                Some(ExtractedReviewTasks::InvalidJson(reason)) => {
                    let mut response = ReviewProviderPlanResponse::success();
                    response.extraction_kind = Some("invalid_json".to_string());
                    response.reason = Some(reason);
                    response
                }
                None => {
                    let mut response = ReviewProviderPlanResponse::success();
                    response.extraction_kind = Some("none".to_string());
                    response
                }
            }
        }
        "parse_review_tasks" => {
            let text = request.text.unwrap_or_default();
            let max_workers = request.max_workers.unwrap_or(1).max(1) as usize;
            extraction_response_from_task_extraction(parse_review_tasks(
                &text,
                &request.allowed_files,
                max_workers,
            ))
        }
        _ => ReviewProviderPlanResponse::error("unsupported_operation", "Unsupported provider plan operation"),
    }
}

pub fn reduce_event(request: ReviewProviderReduceRequest) -> ReviewProviderReduceResponse {
    if request.schema_version != 1 {
        return ReviewProviderReduceResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    match request.operation.as_str() {
        "classify_review_outcome" => {
            let text = request.text.unwrap_or_default();
            let mut response = ReviewProviderReduceResponse::success();
            match classify_review_outcome(&text) {
                ReviewFindingsState::Issues => response.findings_state = Some("issues".to_string()),
                ReviewFindingsState::Clean => response.findings_state = Some("clean".to_string()),
                ReviewFindingsState::Inconclusive(reason) => {
                    response.findings_state = Some("inconclusive".to_string());
                    response.reason = Some(reason);
                }
            }
            response
        }
        _ => ReviewProviderReduceResponse::error("unsupported_operation", "Unsupported provider reduce operation"),
    }
}

fn extraction_response_from_parsed(result: ParsedTasksResult) -> ReviewProviderPlanResponse {
    match result {
        ParsedTasksResult::Tasks(tasks) => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("tasks".to_string());
            response.tasks = Some(tasks);
            response
        }
        ParsedTasksResult::InvalidJson(reason) => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("invalid_json".to_string());
            response.reason = Some(reason);
            response
        }
    }
}

fn extraction_response_from_task_extraction(result: TaskExtraction) -> ReviewProviderPlanResponse {
    match result {
        TaskExtraction::Tasks(tasks) => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("tasks".to_string());
            response.tasks = Some(tasks);
            response
        }
        TaskExtraction::NoFixes => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("no_fixes".to_string());
            response
        }
        TaskExtraction::InvalidJson(reason) => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("invalid_json".to_string());
            response.reason = Some(reason);
            response
        }
        TaskExtraction::NoPayload(reason) => {
            let mut response = ReviewProviderPlanResponse::success();
            response.extraction_kind = Some("no_payload".to_string());
            response.reason = Some(reason);
            response
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_prompt_returns_explicit_scope_and_against_ref() {
        let response = plan_step(ReviewProviderPlanRequest {
            schema_version: 1,
            operation: "parse_prompt".to_string(),
            prompt: Some("[REVIEW_SCOPE:staged] [AGAINST:HEAD~2] Review staged diff".to_string()),
            text: None,
            allowed_files: Vec::new(),
            max_workers: None,
            against_ref: None,
        });
        assert_eq!(response.explicit_scope.as_deref(), Some("staged"));
        assert_eq!(response.against_ref.as_deref(), Some("HEAD~2"));
        assert_eq!(response.clean_prompt.as_deref(), Some("Review staged diff"));
    }

    #[test]
    fn reduce_event_classifies_review_outcome() {
        let response = reduce_event(ReviewProviderReduceRequest {
            schema_version: 1,
            operation: "classify_review_outcome".to_string(),
            text: Some("No critical issues in module A, but a security vulnerability remains in auth flow.".to_string()),
        });
        assert_eq!(response.findings_state.as_deref(), Some("issues"));
    }
}
