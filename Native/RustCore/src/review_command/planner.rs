use super::models::{ReviewCommandConfig, ReviewCommandPlanRequest, ReviewCommandPlanResponse};

pub fn plan_command(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    match request.action.as_str() {
        "start" => plan_start(request),
        "configure" => plan_configure(request),
        "dismiss" => plan_dismiss(request),
        "comment" => plan_comment(request),
        "apply_fix" | "verify_finding" | "prepare_patch" | "verify_patch" | "apply_patch"
        | "revalidate_finding" | "rollback_patch" | "close_finding" | "open_pr"
        | "merge_pr" | "resolve_conflicts" => plan_patch_action(request),
        _ => ReviewCommandPlanResponse::error(format!("Unsupported code review command: {}", request.action)),
    }
}

fn plan_start(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    if !request.workspace_available {
        return ReviewCommandPlanResponse::error("No active workspace is available for code review");
    }
    let session_id = sanitize_session_id(request.session_id)
        .unwrap_or_else(|| generated_session_id(&request.payload));
    let mut response = ReviewCommandPlanResponse::success("start");
    response.session_id = Some(session_id);
    response.config = Some(resolve_config(&request.payload, request.default_config));
    response.deferred = true;
    response
}

fn plan_configure(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    let Some(session_id) = sanitize_session_id(request.session_id) else {
        return ReviewCommandPlanResponse::error("Missing session_id for configure");
    };
    if !request.snapshot_exists {
        return ReviewCommandPlanResponse::error("Review session not found");
    }
    let current = request.current_config.unwrap_or(request.default_config);
    let mut response = ReviewCommandPlanResponse::success("configure");
    response.session_id = Some(session_id);
    response.config = Some(resolve_config(&request.payload, current));
    response
}

fn plan_dismiss(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    let finding_id = trim(request.payload.get("finding_id"));
    if finding_id.is_empty() {
        return ReviewCommandPlanResponse::error("Missing finding_id for dismiss");
    }
    let mut response = ReviewCommandPlanResponse::success("dismiss");
    response.finding_id = Some(finding_id);
    response.reason = Some(
        if trim(request.payload.get("reason")).is_empty() {
            "dismissed".to_string()
        } else {
            trim(request.payload.get("reason"))
        }
    );
    response
}

fn plan_comment(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    let finding_id = trim(request.payload.get("finding_id"));
    let content = trim(request.payload.get("content"));
    if finding_id.is_empty() || content.is_empty() {
        return ReviewCommandPlanResponse::error("Missing finding_id or content for comment");
    }
    let mut response = ReviewCommandPlanResponse::success("comment");
    response.finding_id = Some(finding_id);
    response.author = Some(if trim(request.payload.get("author")).is_empty() {
        "agent".to_string()
    } else {
        trim(request.payload.get("author"))
    });
    response.content = Some(content);
    response
}

fn plan_patch_action(request: ReviewCommandPlanRequest) -> ReviewCommandPlanResponse {
    let Some(session_id) = sanitize_session_id(request.session_id) else {
        return ReviewCommandPlanResponse::error("Missing session_id for patch command");
    };
    let finding_id = trim(request.payload.get("finding_id"));
    if finding_id.is_empty() {
        return ReviewCommandPlanResponse::error("Missing finding_id for patch command");
    }
    let mut response = ReviewCommandPlanResponse::success("patch_action");
    response.session_id = Some(session_id);
    response.finding_id = Some(finding_id);
    response.action = Some(request.action);
    response
}

fn resolve_config(payload: &std::collections::HashMap<String, String>, fallback: ReviewCommandConfig) -> ReviewCommandConfig {
    ReviewCommandConfig {
        max_workers: payload
            .get("max_workers")
            .and_then(|value| value.trim().parse::<i32>().ok())
            .unwrap_or(fallback.max_workers),
        max_rounds: payload
            .get("max_rounds")
            .and_then(|value| value.trim().parse::<i32>().ok())
            .unwrap_or(fallback.max_rounds),
        analysis_backend: non_empty(payload.get("analysis_backend")).unwrap_or(fallback.analysis_backend),
        execution_backend: non_empty(payload.get("execution_backend")).unwrap_or(fallback.execution_backend),
        analysis_only: payload
            .get("analysis_only")
            .and_then(|value| parse_bool(value))
            .unwrap_or(fallback.analysis_only),
    }
}

fn parse_bool(value: &str) -> Option<bool> {
    match value.trim().to_lowercase().as_str() {
        "1" | "true" | "yes" | "y" => Some(true),
        "0" | "false" | "no" | "n" => Some(false),
        _ => None,
    }
}

fn sanitize_session_id(session_id: Option<String>) -> Option<String> {
    let session_id = session_id.map(|value| value.trim().to_string()).filter(|value| !value.is_empty())?;
    let mut chars = session_id.chars();
    let first = chars.next()?;
    if !first.is_ascii_alphanumeric() || session_id.len() > 128 {
        return None;
    }
    if chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_') {
        Some(session_id)
    } else {
        None
    }
}

fn trim(value: Option<&String>) -> String {
    value.map(|value| value.trim().to_string()).unwrap_or_default()
}

fn non_empty(value: Option<&String>) -> Option<String> {
    let value = trim(value);
    if value.is_empty() { None } else { Some(value) }
}

fn generated_session_id(payload: &std::collections::HashMap<String, String>) -> String {
    let prefix = non_empty(payload.get("session_prefix"))
        .unwrap_or_else(|| "review".to_string())
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
        .collect::<String>();
    let normalized_prefix = if prefix.is_empty() {
        "review".to_string()
    } else {
        prefix
    };
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    format!("{normalized_prefix}-{:x}", nanos)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::review_command::models::{ReviewCommandConfig, ReviewCommandPlanRequest};
    use std::collections::HashMap;

    fn default_config() -> ReviewCommandConfig {
        ReviewCommandConfig {
            max_workers: 6,
            max_rounds: 3,
            analysis_backend: "codex".to_string(),
            execution_backend: "codex".to_string(),
            analysis_only: false,
        }
    }

    #[test]
    fn plan_start_normalizes_config_and_marks_deferred() {
        let response = plan_command(ReviewCommandPlanRequest {
            schema_version: 1,
            action: "start".to_string(),
            session_id: Some("session-1".to_string()),
            payload: HashMap::from([
                ("max_workers".to_string(), "4".to_string()),
                ("analysis_only".to_string(), "true".to_string()),
            ]),
            workspace_available: true,
            snapshot_exists: false,
            current_config: None,
            default_config: default_config(),
        });
        assert!(!response.is_error);
        assert_eq!(response.kind, "start");
        assert!(response.deferred);
        assert_eq!(response.config.as_ref().map(|config| config.max_workers), Some(4));
        assert_eq!(response.config.as_ref().map(|config| config.analysis_only), Some(true));
    }

    #[test]
    fn plan_configure_requires_existing_snapshot() {
        let response = plan_command(ReviewCommandPlanRequest {
            schema_version: 1,
            action: "configure".to_string(),
            session_id: Some("session-1".to_string()),
            payload: HashMap::new(),
            workspace_available: true,
            snapshot_exists: false,
            current_config: None,
            default_config: default_config(),
        });
        assert!(response.is_error);
    }

    #[test]
    fn plan_dismiss_requires_finding_and_defaults_reason() {
        let response = plan_command(ReviewCommandPlanRequest {
            schema_version: 1,
            action: "dismiss".to_string(),
            session_id: Some("session-1".to_string()),
            payload: HashMap::from([("finding_id".to_string(), "finding-1".to_string())]),
            workspace_available: true,
            snapshot_exists: true,
            current_config: None,
            default_config: default_config(),
        });
        assert!(!response.is_error);
        assert_eq!(response.kind, "dismiss");
        assert_eq!(response.finding_id.as_deref(), Some("finding-1"));
        assert_eq!(response.reason.as_deref(), Some("dismissed"));
    }

    #[test]
    fn plan_patch_action_requires_session_and_finding() {
        let response = plan_command(ReviewCommandPlanRequest {
            schema_version: 1,
            action: "apply_patch".to_string(),
            session_id: Some("session-1".to_string()),
            payload: HashMap::from([("finding_id".to_string(), "finding-1".to_string())]),
            workspace_available: true,
            snapshot_exists: true,
            current_config: None,
            default_config: default_config(),
        });
        assert!(!response.is_error);
        assert_eq!(response.kind, "patch_action");
        assert_eq!(response.session_id.as_deref(), Some("session-1"));
        assert_eq!(response.finding_id.as_deref(), Some("finding-1"));
        assert_eq!(response.action.as_deref(), Some("apply_patch"));
    }

    #[test]
    fn plan_start_generates_prefixed_session_when_missing() {
        let response = plan_command(ReviewCommandPlanRequest {
            schema_version: 1,
            action: "start".to_string(),
            session_id: None,
            payload: HashMap::from([("session_prefix".to_string(), "panel".to_string())]),
            workspace_available: true,
            snapshot_exists: false,
            current_config: None,
            default_config: default_config(),
        });
        assert!(!response.is_error);
        assert_eq!(response.kind, "start");
        assert!(response.session_id.as_deref().unwrap_or_default().starts_with("panel-"));
    }
}
