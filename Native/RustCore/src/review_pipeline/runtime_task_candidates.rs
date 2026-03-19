use super::candidates::{candidate_from_task, ReviewCandidateFromTaskRequest};
use super::models::ReviewTask;
use crate::review_models::ReviewCoreErrorPayload;
use crate::review_verify::verify_candidates;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeTaskCandidatesRequest {
    pub schema_version: i32,
    pub tasks: Vec<ReviewTask>,
    pub round: i32,
    pub workspace_path: String,
    pub scope_files: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeTaskCandidatesResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub callback: Option<Value>,
}

impl ReviewRuntimeTaskCandidatesResponse {
    pub fn success(callback: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            callback: Some(callback),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            callback: None,
        }
    }
}

pub fn reduce_prepare_task_candidates(
    request: ReviewRuntimeTaskCandidatesRequest,
) -> ReviewRuntimeTaskCandidatesResponse {
    if request.schema_version != 1 {
        return ReviewRuntimeTaskCandidatesResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let mut candidates = Vec::with_capacity(request.tasks.len());
    let prefix = format!("r{}-", request.round);
    for task in request.tasks {
        let task_value = serde_json::to_value(&task)
            .map_err(|err| err.to_string())
            .map_err(|message| ReviewRuntimeTaskCandidatesResponse::error("encode_failed", &message));
        let Ok(task_value) = task_value else {
            return task_value.err().unwrap();
        };
        let response = candidate_from_task(ReviewCandidateFromTaskRequest {
            schema_version: 1,
            task: task_value,
            prefix: prefix.clone(),
        });
        if response.error.is_some() {
            return ReviewRuntimeTaskCandidatesResponse::error(
                "candidate_build_failed",
                response.error.as_ref().map(|err| err.message.as_str()).unwrap_or("candidate build failed"),
            );
        }
        candidates.push(response.candidate.unwrap_or(Value::Null));
    }

    let verification_results = match verify_candidates(
        candidates.clone(),
        &request.workspace_path,
        request.scope_files.clone(),
    ) {
        Ok(results) => results,
        Err(message) => {
            return ReviewRuntimeTaskCandidatesResponse::error("verify_failed", &message)
        }
    };

    let mut events = Vec::new();
    let mut promoted_findings = Vec::new();
    for candidate in &mut candidates {
        let candidate_id = candidate.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
        events.push(event(
            "candidate_added",
            candidate
                .get("filePath")
                .and_then(Value::as_str)
                .unwrap_or("unknown")
                .to_string(),
            json!({"candidate_id": candidate_id.clone()}),
        ));
        if let Some(result) = verification_results.iter().find(|item| item.candidate_id == candidate_id) {
            candidate["verificationStatus"] = json!(result.status);
            candidate["verificationMethod"] = json!(result.method);
            candidate["verificationReport"] = json!(result.report);
            candidate["falsePositiveReason"] = result
                .false_positive_reason
                .clone()
                .map(Value::String)
                .unwrap_or(Value::Null);
            if result.status == "verified" {
                candidate["verifiedAt"] = json!(apple_reference_seconds());
                events.push(event(
                    "candidate_verified",
                    format!("Candidate {} verified", candidate_id),
                    json!({"candidate_id": candidate_id}),
                ));
                let finding = candidate_to_finding(candidate.clone());
                events.push(event(
                    "finding_added",
                    finding
                        .get("filePath")
                        .and_then(Value::as_str)
                        .unwrap_or("unknown")
                        .to_string(),
                    json!({"finding_id": finding.get("id").and_then(Value::as_str).unwrap_or_default()}),
                ));
                promoted_findings.push(finding);
            } else if result.status == "rejected_false_positive" {
                events.push(event(
                    "candidate_rejected",
                    format!("Candidate {} rejected", candidate_id),
                    json!({"candidate_id": candidate_id}),
                ));
            }
        }
    }

    ReviewRuntimeTaskCandidatesResponse::success(json!({
        "kind": "prepare_task_candidates",
        "candidates": candidates,
        "promotedFindings": promoted_findings,
        "events": events,
    }))
}

fn candidate_to_finding(candidate: Value) -> Value {
    json!({
        "id": candidate.get("id").cloned().unwrap_or(Value::Null),
        "severity": candidate.get("severity").cloned().unwrap_or_else(|| json!("warning")),
        "category": candidate.get("category").cloned().unwrap_or_else(|| json!("other")),
        "origin": candidate.get("origin").cloned().unwrap_or_else(|| json!("reviewer")),
        "filePath": candidate.get("filePath").cloned().unwrap_or(Value::Null),
        "lineNumber": candidate.get("lineNumber").cloned().unwrap_or(Value::Null),
        "endLineNumber": candidate.get("endLineNumber").cloned().unwrap_or(Value::Null),
        "message": candidate.get("message").cloned().unwrap_or(Value::Null),
        "suggestedFix": candidate.get("reproOrReasoning").cloned().unwrap_or(Value::Null),
        "expectedInvariant": candidate.get("expectedInvariant").cloned().unwrap_or(Value::Null),
        "reproOrReasoning": candidate.get("reproOrReasoning").cloned().unwrap_or(Value::Null),
        "confidence": candidate.get("confidence").cloned().unwrap_or(Value::Null),
        "evidence": candidate.get("evidence").cloned().unwrap_or(Value::Null),
        "sourceTool": candidate.get("sourceTool").cloned().unwrap_or(Value::Null),
        "blocking": candidate.get("severity").and_then(Value::as_str) == Some("critical"),
        "status": "open",
        "verificationReport": candidate.get("verificationReport").cloned().unwrap_or(Value::Null),
        "verifiedAt": candidate.get("verifiedAt").cloned().unwrap_or(Value::Null),
        "verificationMethod": candidate.get("verificationMethod").cloned().unwrap_or(Value::Null),
        "falsePositiveReason": Value::Null,
        "patchArtifactId": Value::Null,
        "comments": [],
        "createdAt": candidate.get("createdAt").cloned().unwrap_or_else(|| json!(0.0)),
    })
}

fn event(event_type: &str, detail: String, metadata: Value) -> Value {
    let timestamp = apple_reference_seconds();
    json!({
        "id": format!("runtime-event-{event_type}-{timestamp:.6}"),
        "type": event_type,
        "timestamp": timestamp,
        "detail": detail,
        "metadata": metadata.as_object().cloned().unwrap_or_default(),
    })
}

fn apple_reference_seconds() -> f64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
        - 978_307_200.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn reduce_prepare_task_candidates_builds_candidates_and_promotes_verified_ones() {
        let root = std::env::temp_dir().join(format!(
            "review-runtime-candidates-{}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("Service.swift"), "fatalError(\"boom\")\n").unwrap();

        let response = reduce_prepare_task_candidates(ReviewRuntimeTaskCandidatesRequest {
            schema_version: 1,
            tasks: vec![ReviewTask {
                id: "task-1".to_string(),
                description: "fatal crash path".to_string(),
                files: vec!["Service.swift".to_string()],
                severity: "critical".to_string(),
                category: Some("correctness".to_string()),
                line_number: Some(1),
                end_line_number: None,
                origin: "reviewer".to_string(),
                confidence: Some(0.9),
                evidence: Some("fatalError".to_string()),
                expected_invariant: None,
                repro_or_reasoning: None,
                source_tool: None,
                blocking: Some(true),
            }],
            round: 2,
            workspace_path: root.to_str().unwrap().to_string(),
            scope_files: vec!["Service.swift".to_string()],
        });

        let callback = response.callback.unwrap();
        assert_eq!(callback["candidates"].as_array().unwrap().len(), 1);
        assert_eq!(callback["candidates"][0]["id"].as_str(), Some("r2-task-1"));
        assert_eq!(callback["candidates"][0]["verificationStatus"].as_str(), Some("verified"));
        assert_eq!(callback["promotedFindings"].as_array().unwrap().len(), 1);
    }
}
