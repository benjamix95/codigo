use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCandidateFromFindingRequest {
    pub schema_version: i32,
    pub finding: Value,
    pub signal_type: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCandidateFromTaskRequest {
    pub schema_version: i32,
    pub task: Value,
    pub prefix: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewCandidateRuntimeResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub candidate: Option<Value>,
}

impl ReviewCandidateRuntimeResponse {
    pub fn success(candidate: Value) -> Self {
        Self {
            schema_version: 1,
            error: None,
            candidate: Some(candidate),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            candidate: None,
        }
    }
}

pub fn candidate_from_finding(
    request: ReviewCandidateFromFindingRequest,
) -> ReviewCandidateRuntimeResponse {
    if request.schema_version != 1 {
        return ReviewCandidateRuntimeResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let finding = request.finding;
    let candidate = json!({
        "id": required_str(&finding, "id").unwrap_or_default(),
        "severity": finding.get("severity").cloned().unwrap_or_else(|| json!("warning")),
        "category": finding.get("category").cloned().unwrap_or_else(|| json!("other")),
        "origin": finding.get("origin").cloned().unwrap_or_else(|| json!("reviewer")),
        "filePath": required_str(&finding, "filePath").unwrap_or("unknown").to_string(),
        "lineNumber": finding.get("lineNumber").cloned().unwrap_or(Value::Null),
        "endLineNumber": finding.get("endLineNumber").cloned().unwrap_or(Value::Null),
        "message": required_str(&finding, "message").unwrap_or_default(),
        "evidence": finding.get("evidence").cloned().unwrap_or(Value::Null),
        "expectedInvariant": first_non_null(&finding, &["expectedInvariant", "verificationReport"]),
        "reproOrReasoning": first_non_null(&finding, &["reproOrReasoning", "suggestedFix"]),
        "confidence": finding.get("confidence").cloned().unwrap_or(Value::Null),
        "sourceTool": finding.get("sourceTool").cloned().unwrap_or(Value::Null),
        "signalType": request.signal_type,
        "verificationStatus": "new",
        "verificationMethod": Value::Null,
        "verificationReport": Value::Null,
        "falsePositiveReason": Value::Null,
        "createdAt": finding.get("createdAt").cloned().unwrap_or_else(|| json!(0.0)),
        "verifiedAt": Value::Null,
    });
    ReviewCandidateRuntimeResponse::success(candidate)
}

pub fn candidate_from_task(
    request: ReviewCandidateFromTaskRequest,
) -> ReviewCandidateRuntimeResponse {
    if request.schema_version != 1 {
        return ReviewCandidateRuntimeResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }
    let task = request.task;
    let task_id = required_str(&task, "id").unwrap_or_default();
    let description = required_str(&task, "description").unwrap_or_default();
    let files = task
        .get("files")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let file_path = files
        .first()
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_string();
    let origin = required_str(&task, "origin")
        .unwrap_or("reviewer")
        .to_string();
    let category = task
        .get("category")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(|value| value.trim().to_string())
        .unwrap_or_else(|| infer_category(description));
    let severity = normalize_severity(required_str(&task, "severity").unwrap_or("warning"));
    let signal_type = if origin == "audit_tool" {
        "pattern"
    } else {
        "semantic"
    };
    let candidate = json!({
        "id": format!("{}{}", request.prefix, task_id),
        "severity": severity,
        "category": category,
        "origin": origin,
        "filePath": file_path,
        "lineNumber": task.get("lineNumber").cloned().unwrap_or(Value::Null),
        "endLineNumber": task.get("endLineNumber").cloned().unwrap_or(Value::Null),
        "message": description,
        "evidence": task.get("evidence").cloned().unwrap_or(Value::Null),
        "expectedInvariant": task.get("expectedInvariant").cloned().unwrap_or(Value::Null),
        "reproOrReasoning": task.get("reproOrReasoning").cloned().unwrap_or(Value::Null),
        "confidence": task.get("confidence").cloned().unwrap_or(Value::Null),
        "sourceTool": task.get("sourceTool").cloned().unwrap_or(Value::Null),
        "signalType": signal_type,
        "verificationStatus": "new",
        "verificationMethod": Value::Null,
        "verificationReport": Value::Null,
        "falsePositiveReason": Value::Null,
        "createdAt": 0.0,
        "verifiedAt": Value::Null,
    });
    ReviewCandidateRuntimeResponse::success(candidate)
}

fn required_str<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

fn first_non_null(value: &Value, keys: &[&str]) -> Value {
    for key in keys {
        if let Some(candidate) = value.get(*key) {
            if !candidate.is_null() {
                return candidate.clone();
            }
        }
    }
    Value::Null
}

fn normalize_severity(raw: &str) -> &'static str {
    match raw.to_lowercase().as_str() {
        "critical" | "error" | "high" => "critical",
        "warning" | "medium" => "warning",
        "suggestion" | "low" | "info" => "suggestion",
        _ => "warning",
    }
}

fn infer_category(description: &str) -> String {
    let lower = description.to_lowercase();
    if lower.contains("security") || lower.contains("vulnerability") || lower.contains("injection")
    {
        return "security".to_string();
    }
    if lower.contains("race")
        || lower.contains("deadlock")
        || lower.contains("thread")
        || lower.contains("concurrency")
    {
        return "concurrency".to_string();
    }
    if lower.contains("regression")
        || lower.contains("crash")
        || lower.contains("fatal")
        || lower.contains("force unwrap")
    {
        return "regression".to_string();
    }
    if lower.contains("performance") || lower.contains("slow") || lower.contains("o(n") {
        return "performance".to_string();
    }
    if lower.contains("test") || lower.contains("coverage") {
        return "tests".to_string();
    }
    if lower.contains("style")
        || lower.contains("naming")
        || lower.contains("format")
        || lower.contains("architecture")
        || lower.contains("coupling")
        || lower.contains("refactor")
        || lower.contains("doc")
        || lower.contains("comment")
    {
        return "maintainability".to_string();
    }
    "correctness".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn candidate_from_finding_uses_report_and_fix_fallbacks() {
        let response = candidate_from_finding(ReviewCandidateFromFindingRequest {
            schema_version: 1,
            finding: json!({
                "id": "finding-1",
                "severity": "warning",
                "category": "correctness",
                "origin": "reviewer",
                "filePath": "File.swift",
                "message": "message",
                "verificationReport": "report",
                "suggestedFix": "fix"
            }),
            signal_type: "pattern".to_string(),
        });
        let candidate = response.candidate.unwrap();
        assert_eq!(candidate["expectedInvariant"].as_str(), Some("report"));
        assert_eq!(candidate["reproOrReasoning"].as_str(), Some("fix"));
        assert_eq!(candidate["signalType"].as_str(), Some("pattern"));
    }

    #[test]
    fn candidate_from_task_derives_category_and_signal_type() {
        let response = candidate_from_task(ReviewCandidateFromTaskRequest {
            schema_version: 1,
            task: json!({
                "id": "task-1",
                "description": "Security vulnerability in auth flow",
                "files": ["Auth.swift"],
                "severity": "high",
                "origin": "audit_tool"
            }),
            prefix: "r1-".to_string(),
        });
        let candidate = response.candidate.unwrap();
        assert_eq!(candidate["id"].as_str(), Some("r1-task-1"));
        assert_eq!(candidate["severity"].as_str(), Some("critical"));
        assert_eq!(candidate["category"].as_str(), Some("security"));
        assert_eq!(candidate["signalType"].as_str(), Some("pattern"));
    }
}
