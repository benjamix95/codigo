use super::models::ReviewTask;
use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewFixStagePlanRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub resolved_scope: Option<String>,
    pub against_ref: Option<String>,
    #[serde(default)]
    pub tasks: Vec<ReviewTask>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewFixStagePlanResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub pipeline_scope: Option<String>,
    pub task_batches: Vec<Vec<ReviewTask>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewFixStageEventRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub event_kind: String,
    pub task_id: Option<String>,
    pub title: Option<String>,
    pub agent_name: Option<String>,
    pub error: Option<String>,
    pub delta: Option<String>,
    pub replacement: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewFixStageEventResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub raw_type: Option<String>,
    pub raw_payload: Option<std::collections::HashMap<String, String>>,
    pub text_delta: Option<String>,
    pub text_replace: Option<String>,
}

impl ReviewFixStagePlanResponse {
    fn success() -> Self {
        Self {
            schema_version: 1,
            error: None,
            pipeline_scope: None,
            task_batches: Vec::new(),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            pipeline_scope: None,
            task_batches: Vec::new(),
        }
    }
}

impl ReviewFixStageEventResponse {
    fn success() -> Self {
        Self {
            schema_version: 1,
            error: None,
            raw_type: None,
            raw_payload: None,
            text_delta: None,
            text_replace: None,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        let mut response = Self::success();
        response.error = Some(ReviewCoreErrorPayload::new(code, message));
        response
    }
}

pub fn plan_fix_stage(request: ReviewFixStagePlanRequest) -> ReviewFixStagePlanResponse {
    if request.schema_version != 1 {
        return ReviewFixStagePlanResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    let mut response = ReviewFixStagePlanResponse::success();
    response.pipeline_scope = Some(resolve_pipeline_scope(
        request.resolved_scope.as_deref(),
        request.against_ref.as_deref(),
    ));
    response.task_batches = non_overlapping_review_task_batches(&request.tasks);
    response
}

pub fn bridge_fix_stage_event(request: ReviewFixStageEventRequest) -> ReviewFixStageEventResponse {
    if request.schema_version != 1 {
        return ReviewFixStageEventResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    let session_id = request.session_id;
    match request.event_kind.as_str() {
        "task_started" => raw_agent_event(
            request.title.unwrap_or_default(),
            "started",
            request.task_id.unwrap_or_default(),
            session_id,
            None,
        ),
        "task_completed" => raw_agent_event(
            request.agent_name.unwrap_or_default(),
            "completed",
            request.task_id.unwrap_or_default(),
            session_id,
            None,
        ),
        "task_failed" => {
            let task_id = request.task_id.unwrap_or_default();
            let error = request.error.unwrap_or_default();
            let mut response = raw_agent_event(
                task_id.clone(),
                "failed",
                task_id.clone(),
                session_id,
                Some("failed".to_string()),
            );
            response.text_delta = Some(format!("\n[Task {task_id} failed: {error}]\n"));
            response
        }
        "text_delta" => {
            let mut response = ReviewFixStageEventResponse::success();
            response.text_delta = request.delta;
            response
        }
        "text_replace" => {
            let mut response = ReviewFixStageEventResponse::success();
            response.text_replace = request.replacement;
            response
        }
        _ => ReviewFixStageEventResponse::success(),
    }
}

fn resolve_pipeline_scope(resolved_scope: Option<&str>, against_ref: Option<&str>) -> String {
    if against_ref.is_some() {
        return "against_ref".to_string();
    }
    match resolved_scope.unwrap_or("uncommitted") {
        "staged" => "staged".to_string(),
        "workspace" => "workspace".to_string(),
        _ => "uncommitted".to_string(),
    }
}

fn non_overlapping_review_task_batches(tasks: &[ReviewTask]) -> Vec<Vec<ReviewTask>> {
    let mut batches: Vec<Vec<ReviewTask>> = Vec::new();
    for task in tasks {
        let file_set: HashSet<&str> = task.files.iter().map(String::as_str).collect();
        if let Some(batch_index) = batches.iter().position(|batch| {
            batch.iter().all(|existing| {
                let existing_files: HashSet<&str> =
                    existing.files.iter().map(String::as_str).collect();
                existing_files.is_disjoint(&file_set)
            })
        }) {
            batches[batch_index].push(task.clone());
        } else {
            batches.push(vec![task.clone()]);
        }
    }
    batches
}

fn raw_agent_event(
    title: String,
    detail: &str,
    task_id: String,
    session_id: String,
    status: Option<String>,
) -> ReviewFixStageEventResponse {
    let mut payload = std::collections::HashMap::from([
        ("title".to_string(), title),
        ("detail".to_string(), detail.to_string()),
        ("swarm_id".to_string(), task_id.clone()),
        (
            "group_id".to_string(),
            format!("review-{session_id}-{task_id}"),
        ),
        ("session_id".to_string(), session_id),
    ]);
    if let Some(status) = status {
        payload.insert("status".to_string(), status);
    }
    let mut response = ReviewFixStageEventResponse::success();
    response.raw_type = Some("agent".to_string());
    response.raw_payload = Some(payload);
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    fn task(id: &str, files: &[&str]) -> ReviewTask {
        ReviewTask {
            id: id.to_string(),
            description: format!("Task {id}"),
            files: files.iter().map(|file| file.to_string()).collect(),
            severity: "warning".to_string(),
            category: None,
            line_number: None,
            end_line_number: None,
            origin: "reviewer".to_string(),
            confidence: None,
            evidence: None,
            expected_invariant: None,
            repro_or_reasoning: None,
            source_tool: None,
            blocking: None,
        }
    }

    #[test]
    fn plan_fix_stage_batches_overlapping_files_like_swift() {
        let response = plan_fix_stage(ReviewFixStagePlanRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            resolved_scope: Some("staged".to_string()),
            against_ref: None,
            tasks: vec![
                task("t1", &["a.swift"]),
                task("t2", &["a.swift", "b.swift"]),
                task("t3", &["c.swift"]),
            ],
        });
        assert_eq!(response.pipeline_scope.as_deref(), Some("staged"));
        assert_eq!(response.task_batches.len(), 2);
        assert_eq!(
            response.task_batches[0]
                .iter()
                .map(|item| item.id.as_str())
                .collect::<Vec<_>>(),
            vec!["t1", "t3"]
        );
        assert_eq!(
            response.task_batches[1]
                .iter()
                .map(|item| item.id.as_str())
                .collect::<Vec<_>>(),
            vec!["t2"]
        );
    }

    #[test]
    fn bridge_fix_stage_event_maps_failed_event_and_text() {
        let response = bridge_fix_stage_event(ReviewFixStageEventRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            event_kind: "task_failed".to_string(),
            task_id: Some("task-9".to_string()),
            title: None,
            agent_name: None,
            error: Some("boom".to_string()),
            delta: None,
            replacement: None,
        });
        assert_eq!(response.raw_type.as_deref(), Some("agent"));
        assert_eq!(
            response
                .raw_payload
                .as_ref()
                .and_then(|payload| payload.get("group_id"))
                .map(String::as_str),
            Some("review-session-1-task-9")
        );
        assert_eq!(
            response.text_delta.as_deref(),
            Some("\n[Task task-9 failed: boom]\n")
        );
    }
}
