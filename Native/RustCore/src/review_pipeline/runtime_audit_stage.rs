use super::candidates::{candidate_from_finding, ReviewCandidateFromFindingRequest};
use crate::review_models::ReviewCoreErrorPayload;
use crate::review_verify::verify_candidates;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeAuditStageRequest {
    pub schema_version: i32,
    #[serde(default)]
    pub findings: Vec<Value>,
    #[serde(default)]
    pub results: Vec<Value>,
    pub workspace_path: String,
    #[serde(default)]
    pub scope_files: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewRuntimeAuditStageResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub callback: Option<Value>,
}

impl ReviewRuntimeAuditStageResponse {
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

pub fn reduce_audit_stage(request: ReviewRuntimeAuditStageRequest) -> ReviewRuntimeAuditStageResponse {
    if request.schema_version != 1 {
        return ReviewRuntimeAuditStageResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    let mut candidates = Vec::with_capacity(request.findings.len());
    for finding in &request.findings {
        let response = candidate_from_finding(ReviewCandidateFromFindingRequest {
            schema_version: 1,
            finding: finding.clone(),
            signal_type: "pattern".to_string(),
        });
        if response.error.is_some() {
            return ReviewRuntimeAuditStageResponse::error(
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
        Err(message) => return ReviewRuntimeAuditStageResponse::error("verify_failed", &message),
    };

    let mut candidate_values = candidates;
    let mut promoted_findings = Vec::new();
    for candidate in &mut candidate_values {
        let candidate_id = candidate.get("id").and_then(Value::as_str).unwrap_or_default().to_string();
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
                promoted_findings.push(candidate_to_finding(candidate.clone()));
            }
        }
    }

    let audit_snapshot = build_audit_snapshot(&request.results);
    let events = build_audit_events(&request.results);
    let callback = json!({
        "kind": "run_audit_stage",
        "findings": request.findings,
        "candidates": candidate_values,
        "promotedFindings": promoted_findings,
        "events": events,
        "audit": audit_snapshot,
    });
    ReviewRuntimeAuditStageResponse::success(callback)
}

fn build_audit_snapshot(results: &[Value]) -> Value {
    let mut coverage = Map::new();
    let mut durations = Map::new();
    let mut counts = Map::new();
    let mut adapters = Map::new();
    for result in results {
        let tool_name = result.get("toolName").and_then(Value::as_str).unwrap_or_default();
        coverage.insert(
            tool_name.to_string(),
            json!(result.get("coverageAvailable").and_then(Value::as_bool).unwrap_or(false)),
        );
        durations.insert(
            tool_name.to_string(),
            json!(result.get("durationMs").and_then(Value::as_i64).unwrap_or(0)),
        );
        counts.insert(
            tool_name.to_string(),
            json!(result.get("findings").and_then(Value::as_array).map(|items| items.len()).unwrap_or(0)),
        );
        adapters.insert(
            tool_name.to_string(),
            result.get("adaptersUsed").cloned().unwrap_or_else(|| json!([])),
        );
    }
    Value::Object(Map::from_iter([
        ("toolCoverage".to_string(), Value::Object(coverage)),
        ("toolDurationsMs".to_string(), Value::Object(durations)),
        ("toolFindingsCounts".to_string(), Value::Object(counts)),
        ("toolAdapters".to_string(), Value::Object(adapters)),
    ]))
}

fn build_audit_events(results: &[Value]) -> Vec<Value> {
    let mut events = Vec::new();
    let mut sorted = results.to_vec();
    sorted.sort_by(|lhs, rhs| {
        lhs.get("toolName")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .cmp(rhs.get("toolName").and_then(Value::as_str).unwrap_or_default())
    });
    for result in sorted {
        let tool_name = result.get("toolName").and_then(Value::as_str).unwrap_or_default();
        let summary = result.get("summary").and_then(Value::as_str).unwrap_or_default();
        let coverage = result.get("coverageAvailable").and_then(Value::as_bool).unwrap_or(false);
        let duration_ms = result.get("durationMs").and_then(Value::as_i64).unwrap_or(0);
        let findings_count = result.get("findings").and_then(Value::as_array).map(|items| items.len()).unwrap_or(0);
        events.push(make_event(
            "audit_completed",
            summary.to_string(),
            json!({
                "tool": tool_name,
                "coverage": if coverage { "true" } else { "false" },
                "duration_ms": duration_ms.to_string(),
                "findings_count": findings_count.to_string(),
            }),
        ));
    }
    events
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

fn make_event(event_type: &str, detail: String, metadata: Value) -> Value {
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
    fn reduce_audit_stage_builds_audit_snapshot_and_promotes_verified_findings() {
        let root = std::env::temp_dir().join(format!(
            "review-runtime-audit-{}",
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("Service.swift"), "fatalError(\"boom\")\n").unwrap();

        let finding = json!({
            "id": "finding-1",
            "severity": "critical",
            "category": "correctness",
            "origin": "audit_tool",
            "filePath": "Service.swift",
            "lineNumber": 1,
            "message": "fatal crash path",
            "evidence": "fatalError",
            "sourceTool": "audit_bug_nil_crash_paths",
            "blocking": true,
            "comments": [],
            "createdAt": 0.0
        });
        let result = json!({
            "toolName": "audit_bug_nil_crash_paths",
            "findings": [finding.clone()],
            "durationMs": 3,
            "coverageAvailable": true,
            "summary": "found one",
            "adaptersUsed": []
        });

        let response = reduce_audit_stage(ReviewRuntimeAuditStageRequest {
            schema_version: 1,
            findings: vec![finding],
            results: vec![result],
            workspace_path: root.to_str().unwrap().to_string(),
            scope_files: vec!["Service.swift".to_string()],
        });

        let callback = response.callback.unwrap();
        assert_eq!(callback["audit"]["toolCoverage"]["audit_bug_nil_crash_paths"].as_bool(), Some(true));
        assert_eq!(callback["candidates"].as_array().unwrap().len(), 1);
        assert_eq!(callback["promotedFindings"].as_array().unwrap().len(), 1);
        assert_eq!(callback["events"].as_array().unwrap().len(), 1);
    }
}
