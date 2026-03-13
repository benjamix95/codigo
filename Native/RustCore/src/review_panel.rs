use crate::review_chat::merge_chat_findings;
use crate::review_command::{
    models::ReviewCommandPlanRequest,
    plan_command,
};
use crate::review_history::{
    derive_history_live_state,
    derive_historical_findings_from_snapshot,
};
use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelSnapshotRequest {
    pub schema_version: i32,
    pub snapshot: Value,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelHistoryLiveRequest {
    pub schema_version: i32,
    pub snapshot: Value,
    #[serde(default)]
    pub worker_plans: Vec<Value>,
    #[serde(default)]
    pub live_cards: Vec<Value>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelChatExtractRequest {
    pub schema_version: i32,
    pub content: String,
    #[serde(default)]
    pub existing_findings: Vec<Value>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelChatExtractResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub found_block: bool,
    pub visible_content: String,
    pub findings: Vec<Value>,
    pub inserted_count: i64,
    pub extracted_count: i64,
}

pub fn plan_panel_launch(request: ReviewCommandPlanRequest) -> crate::review_command::models::ReviewCommandPlanResponse {
    plan_command(request)
}

pub fn derive_panel_history_live(request: ReviewPanelHistoryLiveRequest) -> Value {
    derive_history_live_state(&request.snapshot, &request.worker_plans, &request.live_cards)
}

pub fn derive_panel_history_records(snapshot: Value) -> Vec<Value> {
    derive_historical_findings_from_snapshot(&snapshot)
}

pub fn extract_panel_chat_findings(
    request: ReviewPanelChatExtractRequest,
) -> ReviewPanelChatExtractResponse {
    let Some((range, json_payload)) = extract_findings_block(&request.content) else {
        return ReviewPanelChatExtractResponse::success(
            false,
            request.content,
            request.existing_findings,
            0,
            0,
        );
    };

    let payload: Value = match serde_json::from_str(json_payload) {
        Ok(payload) => payload,
        Err(error) => {
            return ReviewPanelChatExtractResponse::error(
                "decode_failed",
                &error.to_string(),
                request.content,
                request.existing_findings,
                true,
            );
        }
    };

    let extracted = payload
        .get("findings")
        .and_then(Value::as_array)
        .map(|items| {
            items.iter()
                .enumerate()
                .filter_map(|(index, item)| map_chat_finding(item, index))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let merged = merge_chat_findings(&request.existing_findings, &extracted);
    let findings = merged
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or(request.existing_findings);
    let inserted_count = merged
        .get("insertedCount")
        .and_then(Value::as_i64)
        .unwrap_or(0);

    let mut visible_content = request.content;
    visible_content.replace_range(range, "");
    ReviewPanelChatExtractResponse::success(
        true,
        visible_content.trim().to_string(),
        findings,
        inserted_count,
        extracted.len() as i64,
    )
}

impl ReviewPanelChatExtractResponse {
    pub(crate) fn success(
        found_block: bool,
        visible_content: String,
        findings: Vec<Value>,
        inserted_count: i64,
        extracted_count: i64,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            found_block,
            visible_content,
            findings,
            inserted_count,
            extracted_count,
        }
    }

    pub(crate) fn error(
        code: &str,
        message: &str,
        content: String,
        findings: Vec<Value>,
        found_block: bool,
    ) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            found_block,
            visible_content: content,
            findings,
            inserted_count: 0,
            extracted_count: 0,
        }
    }
}

fn extract_findings_block(content: &str) -> Option<(std::ops::Range<usize>, &str)> {
    let marker = "```review_findings";
    let block_start = content.find(marker)?;
    let marker_end = block_start + marker.len();
    let json_start_rel = content[marker_end..].find('{')?;
    let json_start = marker_end + json_start_rel;
    let closing_rel = content[json_start..].find("```")?;
    let block_end = json_start + closing_rel + 3;
    let json_payload = content[json_start..(json_start + closing_rel)].trim();
    Some((block_start..block_end, json_payload))
}

fn map_chat_finding(raw: &Value, index: usize) -> Option<Value> {
    let file = raw.get("file").and_then(Value::as_str)?.trim();
    let message = raw.get("message").and_then(Value::as_str)?.trim();
    if file.is_empty() || message.is_empty() {
        return None;
    }

    let severity = normalize_severity(raw.get("severity").and_then(Value::as_str));
    let category = normalize_category(raw.get("category").and_then(Value::as_str), message);
    let line = raw.get("line").and_then(Value::as_i64);
    let confidence = raw.get("confidence").and_then(Value::as_f64);
    let suggested_fix = raw
        .get("suggested_fix")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty());
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);

    Some(json!({
        "id": format!("chat-{seed:x}-{index}"),
        "severity": severity,
        "category": category,
        "origin": "reviewer",
        "filePath": file,
        "lineNumber": line,
        "message": message,
        "suggestedFix": suggested_fix,
        "confidence": confidence,
        "evidence": "Structured findings block from review panel chat",
        "sourceTool": "review-panel-chat",
        "blocking": severity == "critical",
        "status": "open",
        "comments": [],
    }))
}

fn normalize_severity(raw: Option<&str>) -> &'static str {
    match raw.unwrap_or("warning").trim().to_lowercase().as_str() {
        "critical" | "error" | "high" => "critical",
        "warning" | "medium" => "warning",
        "suggestion" | "low" => "suggestion",
        "info" => "info",
        _ => "warning",
    }
}

fn normalize_category(raw: Option<&str>, message: &str) -> &'static str {
    match raw.unwrap_or("").trim().to_lowercase().as_str() {
        "correctness" | "bug" => "correctness",
        "regression" => "regression",
        "concurrency" => "concurrency",
        "security" => "security",
        "performance" => "performance",
        "tests" | "testing" => "tests",
        "maintainability" | "style" | "architecture" | "documentation" => "maintainability",
        "other" => "other",
        _ => infer_category(message),
    }
}

fn infer_category(message: &str) -> &'static str {
    let lower = message.to_lowercase();
    if lower.contains("security") || lower.contains("injection") || lower.contains("authorization") {
        "security"
    } else if lower.contains("race") || lower.contains("deadlock") || lower.contains("thread") {
        "concurrency"
    } else if lower.contains("regression") || lower.contains("crash") || lower.contains("retry") {
        "regression"
    } else if lower.contains("performance") || lower.contains("slow") {
        "performance"
    } else if lower.contains("test") || lower.contains("coverage") {
        "tests"
    } else if lower.contains("style") || lower.contains("naming") || lower.contains("refactor") {
        "maintainability"
    } else {
        "correctness"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_panel_chat_findings_removes_block_and_merges_new_findings() {
        let response = extract_panel_chat_findings(ReviewPanelChatExtractRequest {
            schema_version: 1,
            content: "Before\n```review_findings\n{\"findings\":[{\"severity\":\"warning\",\"category\":\"correctness\",\"file\":\"Sources/App.swift\",\"line\":42,\"message\":\"Retry emits a duplicate event\"}]}\n```\nAfter".to_string(),
            existing_findings: Vec::new(),
        });
        assert!(response.error.is_none());
        assert!(response.found_block);
        assert_eq!(response.inserted_count, 1);
        assert_eq!(response.extracted_count, 1);
        assert!(!response.visible_content.contains("```review_findings"));
        assert_eq!(response.findings.len(), 1);
    }

    #[test]
    fn extract_panel_chat_findings_keeps_original_content_when_payload_is_invalid() {
        let content = "```review_findings\n{invalid}\n```".to_string();
        let response = extract_panel_chat_findings(ReviewPanelChatExtractRequest {
            schema_version: 1,
            content: content.clone(),
            existing_findings: Vec::new(),
        });
        assert!(response.error.is_some());
        assert_eq!(response.visible_content, content);
        assert_eq!(response.inserted_count, 0);
    }
}
