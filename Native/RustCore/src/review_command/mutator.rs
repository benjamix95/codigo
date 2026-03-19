use super::config::config_from_snapshot;
use super::mutator_configure::configure_snapshot;
use super::mutator_support::{
    event_with_reference_timestamp, find_finding, find_patch, reference_timestamp, required,
};
use super::models::{ReviewCommandMutationRequest, ReviewCommandMutationResponse};
use serde_json::{json, Value};
use crate::review_session::build_outcome;

pub fn mutate_snapshot(request: ReviewCommandMutationRequest) -> ReviewCommandMutationResponse {
    let Some(findings) = request.snapshot.get("findings").and_then(Value::as_array) else {
        return ReviewCommandMutationResponse::error("Snapshot findings are missing");
    };
    let Some(events) = request.snapshot.get("events").and_then(Value::as_array) else {
        return ReviewCommandMutationResponse::error("Snapshot events are missing");
    };
    let patches = request
        .snapshot
        .get("patches")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let timestamp = reference_timestamp(&request.snapshot);
    let mut findings = findings.clone();
    let mut events = events.clone();
    let mut patches = patches;
    let mut resolved_config = config_from_snapshot(&request.snapshot).ok();

    let result = match request.action.as_str() {
        "apply_fix" => apply_fix(&mut findings, &mut events, &request.payload, timestamp),
        "dismiss" => dismiss(&mut findings, &mut events, &request.payload, timestamp),
        "comment" => comment(&mut findings, &mut events, &request.payload, timestamp),
        "configure" => configure_snapshot(&mut events, &request.payload, &mut resolved_config, timestamp),
        "close_finding" => close_finding(
            &mut findings,
            &mut events,
            &patches,
            &request.payload,
            timestamp,
        ),
        "upsert_patch" => upsert_patch(
            &mut findings,
            &mut patches,
            &mut events,
            &request.payload,
            timestamp,
        ),
        _ => return ReviewCommandMutationResponse::error("Unsupported snapshot mutation"),
    };
    if let Err(error) = result {
        return error;
    }

    let snapshot = canonicalized_snapshot(
        request.snapshot,
        findings.clone(),
        patches.clone(),
        events.clone(),
        resolved_config.clone(),
        timestamp,
    );
    ReviewCommandMutationResponse::success(findings, patches, events, resolved_config, snapshot)
}

fn canonicalized_snapshot(
    mut snapshot: Value,
    findings: Vec<Value>,
    patches: Vec<Value>,
    events: Vec<Value>,
    config: Option<super::models::ReviewCommandConfig>,
    timestamp: f64,
) -> Value {
    snapshot["findings"] = Value::Array(findings);
    snapshot["patches"] = Value::Array(patches);
    snapshot["events"] = Value::Array(events);
    if let Some(config) = config {
        snapshot["config"] = serde_json::to_value(config).unwrap_or(Value::Null);
    }
    snapshot["mutationSequence"] =
        json!(snapshot.get("mutationSequence").and_then(Value::as_u64).unwrap_or(0) + 1);
    snapshot["lastUpdatedAt"] = json!(timestamp);
    snapshot["outcome"] = build_outcome(&snapshot, None);
    snapshot
}

fn apply_fix(
    findings: &mut [Value],
    events: &mut Vec<Value>,
    payload: &std::collections::HashMap<String, String>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let finding = find_finding(findings, &finding_id)?;
    finding["status"] = Value::String("fix_applied".to_string());
    events.push(event_with_reference_timestamp(
        "finding_fix_applied",
        format!("Fix applied for finding {}", finding_id),
        json!({ "finding_id": finding_id }),
        timestamp,
    ));
    Ok(())
}

fn dismiss(
    findings: &mut [Value],
    events: &mut Vec<Value>,
    payload: &std::collections::HashMap<String, String>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let reason = payload.get("reason").map(|v| v.trim()).filter(|v| !v.is_empty()).unwrap_or("dismissed");
    let finding = find_finding(findings, &finding_id)?;
    finding["status"] = Value::String(if reason.eq_ignore_ascii_case("wont_fix") {
        "wont_fix".to_string()
    } else {
        "dismissed".to_string()
    });
    events.push(event_with_reference_timestamp(
        "finding_dismissed",
        format!("Finding {} dismissed: {}", finding_id, reason),
        json!({ "finding_id": finding_id, "reason": reason }),
        timestamp,
    ));
    Ok(())
}

fn comment(
    findings: &mut [Value],
    events: &mut Vec<Value>,
    payload: &std::collections::HashMap<String, String>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let content = required(payload, "content")?;
    let author = payload.get("author").map(|v| v.trim()).filter(|v| !v.is_empty()).unwrap_or("agent");
    let finding = find_finding(findings, &finding_id)?;
    let comments = finding
        .get_mut("comments")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| ReviewCommandMutationResponse::error("Finding comments are missing"))?;
    let comment_id = format!("command-comment-{}-{}", finding_id, comments.len() + 1);
    comments.push(json!({
        "id": comment_id,
        "author": author,
        "content": content,
        "createdAt": timestamp,
    }));
    events.push(event_with_reference_timestamp(
        "finding_commented",
        "Comment added from command bus".to_string(),
        json!({ "finding_id": finding_id }),
        timestamp,
    ));
    Ok(())
}

fn close_finding(
    findings: &mut [Value],
    events: &mut Vec<Value>,
    patches: &[Value],
    payload: &std::collections::HashMap<String, String>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let reason = payload
        .get("reason")
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .unwrap_or("closed");
    let finding = find_finding(findings, &finding_id)?;
    let current_status = finding
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("open");
    let can_close = match current_status {
        "merged" | "dismissed" | "wont_fix" | "closed" => true,
        "patch_applied" | "fix_applied" => find_patch(patches, &finding_id)
            .and_then(|patch| patch.get("validationStatus").and_then(Value::as_str))
            == Some("passed"),
        _ => false,
    };
    if !can_close {
        return Err(ReviewCommandMutationResponse::error(
            "Finding cannot be closed until it is merged, dismissed, or validated after apply",
        ));
    }
    finding["status"] = Value::String("closed".to_string());
    events.push(event_with_reference_timestamp(
        "outcome_published",
        format!("Finding {} closed", finding_id),
        json!({ "finding_id": finding_id, "reason": reason }),
        timestamp,
    ));
    Ok(())
}

fn upsert_patch(
    findings: &mut [Value],
    patches: &mut Vec<Value>,
    events: &mut Vec<Value>,
    payload: &std::collections::HashMap<String, String>,
    timestamp: f64,
) -> Result<(), ReviewCommandMutationResponse> {
    let patch_json = required(payload, "patch_json")?;
    let patch: Value = serde_json::from_str(&patch_json)
        .map_err(|err| ReviewCommandMutationResponse::error(err.to_string()))?;
    let patch_id = patch
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| ReviewCommandMutationResponse::error("Patch id is missing"))?
        .to_string();
    let finding_id = patch
        .get("findingId")
        .and_then(Value::as_str)
        .ok_or_else(|| ReviewCommandMutationResponse::error("Patch findingId is missing"))?
        .to_string();
    let patch_status = patch
        .get("status")
        .and_then(Value::as_str)
        .unwrap_or("draft")
        .to_string();

    if let Some(index) = patches.iter().position(|existing| {
        existing.get("id").and_then(Value::as_str) == Some(patch_id.as_str())
            || existing.get("findingId").and_then(Value::as_str) == Some(finding_id.as_str())
    }) {
        patches[index] = patch.clone();
    } else {
        patches.push(patch.clone());
    }

    let finding = find_finding(findings, &finding_id)?;
    finding["patchArtifactId"] = Value::String(patch_id.clone());
    finding["status"] = Value::String(match patch_status.as_str() {
        "draft" => "patch_preparing",
        "verified" => "patch_ready",
        "applied" => "patch_applied",
        "apply_failed" => "patch_failed",
        "pr_opened" => "pr_opened",
        "merged" => "merged",
        "conflict" | "rolled_back" => "blocked",
        _ => "open",
    }
    .to_string());

    let event_value = match patch_status.as_str() {
        "draft" => event_with_reference_timestamp(
            "patch_prepared",
            format!("Patch prepared for finding {}", finding_id),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "verified" => event_with_reference_timestamp(
            "patch_verified",
            format!("Patch {} verified", patch_id),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "apply_failed" => event_with_reference_timestamp(
            "patch_apply_failed",
            patch.get("applyMessage")
                .and_then(Value::as_str)
                .unwrap_or("Patch apply failed")
                .to_string(),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "pr_opened" => event_with_reference_timestamp(
            "pr_opened",
            patch.get("prURL")
                .and_then(Value::as_str)
                .unwrap_or("Pull request opened")
                .to_string(),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "merged" => event_with_reference_timestamp(
            "pr_merged",
            patch.get("prURL")
                .and_then(Value::as_str)
                .unwrap_or("Patch merged")
                .to_string(),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "conflict" => event_with_reference_timestamp(
            "conflict_detected",
            patch.get("conflicts")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .unwrap_or_default(),
            json!({ "patch_id": patch_id, "finding_id": finding_id }),
            timestamp,
        ),
        "applied" | "rolled_back" => event_with_reference_timestamp(
            "finding_fix_applied",
            format!("Fix applied for finding {}", finding_id),
            json!({ "finding_id": finding_id }),
            timestamp,
        ),
        _ => {
            return Err(ReviewCommandMutationResponse::error(
                "Unsupported patch status for snapshot upsert",
            ))
        }
    };
    events.push(event_value);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_snapshot() -> Value {
        json!({
            "sessionId": "session-1",
            "lastUpdatedAt": "2026-03-11T12:00:00Z",
            "findings": [{
                "id": "finding-1",
                "status": "open",
                "comments": []
            }],
            "patches": [],
            "events": []
        })
    }

    #[test]
    fn dismiss_sets_wont_fix_and_appends_event() {
        let response = mutate_snapshot(ReviewCommandMutationRequest {
            schema_version: 1,
            action: "dismiss".to_string(),
            snapshot: base_snapshot(),
            payload: std::collections::HashMap::from([
                ("finding_id".to_string(), "finding-1".to_string()),
                ("reason".to_string(), "wont_fix".to_string()),
            ]),
        });
        assert!(!response.is_error);
        assert_eq!(
            response.findings.unwrap()[0].get("status").and_then(Value::as_str),
            Some("wont_fix")
        );
        assert!(response.events.unwrap()[0].get("timestamp").and_then(Value::as_f64).is_some());
    }

    #[test]
    fn comment_appends_comment_and_event() {
        let response = mutate_snapshot(ReviewCommandMutationRequest {
            schema_version: 1,
            action: "comment".to_string(),
            snapshot: base_snapshot(),
            payload: std::collections::HashMap::from([
                ("finding_id".to_string(), "finding-1".to_string()),
                ("content".to_string(), "hello".to_string()),
            ]),
        });
        assert!(!response.is_error);
        let findings = response.findings.unwrap();
        let comments = findings[0].get("comments").and_then(Value::as_array).unwrap();
        assert_eq!(comments.len(), 1);
        assert_eq!(comments[0].get("content").and_then(Value::as_str), Some("hello"));
        assert!(comments[0].get("createdAt").and_then(Value::as_f64).is_some());
    }

    #[test]
    fn close_finding_requires_validated_apply_or_terminal_status() {
        let response = mutate_snapshot(ReviewCommandMutationRequest {
            schema_version: 1,
            action: "close_finding".to_string(),
            snapshot: json!({
                "sessionId": "session-1",
                "lastUpdatedAt": "2026-03-11T12:00:00Z",
                "findings": [{
                    "id": "finding-1",
                    "status": "patch_applied",
                    "comments": []
                }],
                "patches": [{
                    "findingId": "finding-1",
                    "validationStatus": "passed"
                }],
                "events": []
            }),
            payload: std::collections::HashMap::from([
                ("finding_id".to_string(), "finding-1".to_string()),
                ("reason".to_string(), "fixed_verified".to_string()),
            ]),
        });
        assert!(!response.is_error);
        assert_eq!(
            response.findings.unwrap()[0].get("status").and_then(Value::as_str),
            Some("closed")
        );
    }

    #[test]
    fn configure_returns_normalized_config_and_event() {
        let response = mutate_snapshot(ReviewCommandMutationRequest {
            schema_version: 1,
            action: "configure".to_string(),
            snapshot: json!({
                "sessionId": "session-1",
                "lastUpdatedAt": "2026-03-11T12:00:00Z",
                "findings": [{
                    "id": "finding-1",
                    "status": "open",
                    "comments": []
                }],
                "patches": [],
                "events": [],
                "config": {
                    "maxWorkers": 2,
                    "maxRounds": 1,
                    "analysisBackend": "codex",
                    "executionBackend": "codex",
                    "analysisOnly": false
                }
            }),
            payload: std::collections::HashMap::from([
                ("max_workers".to_string(), "7".to_string()),
                ("analysis_only".to_string(), "true".to_string()),
            ]),
        });
        assert!(!response.is_error);
        assert_eq!(response.config.as_ref().map(|config| config.max_workers), Some(7));
        assert_eq!(response.config.as_ref().map(|config| config.analysis_only), Some(true));
        let events = response.events.unwrap();
        assert_eq!(events[0].get("type").and_then(Value::as_str), Some("config_updated"));
        assert!(events[0].get("timestamp").and_then(Value::as_f64).is_some());
    }

    #[test]
    fn upsert_patch_updates_findings_patches_and_events() {
        let patch = json!({
            "id": "patch-1",
            "findingId": "finding-1",
            "status": "pr_opened",
            "applyMessage": null,
            "prURL": "https://example.test/pr/1"
        });
        let response = mutate_snapshot(ReviewCommandMutationRequest {
            schema_version: 1,
            action: "upsert_patch".to_string(),
            snapshot: base_snapshot(),
            payload: std::collections::HashMap::from([(
                "patch_json".to_string(),
                patch.to_string(),
            )]),
        });
        assert!(!response.is_error);
        assert_eq!(
            response.findings.unwrap()[0]
                .get("status")
                .and_then(Value::as_str),
            Some("pr_opened")
        );
        assert_eq!(response.patches.as_ref().map(Vec::len), Some(1));
        assert_eq!(
            response.events.unwrap()[0]
                .get("type")
                .and_then(Value::as_str),
            Some("pr_opened")
        );
    }
}
