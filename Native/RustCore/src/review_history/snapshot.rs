use serde_json::Value;
use std::collections::HashMap;

use crate::review_value::get_str;

pub fn derive_historical_findings_from_snapshot(snapshot: &Value) -> Vec<Value> {
    let session_id = snapshot
        .get("sessionId")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let workspace_id = snapshot
        .get("workspacePath")
        .and_then(Value::as_str)
        .unwrap_or("workspace")
        .to_string();
    let patches = snapshot
        .get("patches")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let events = snapshot
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let grouped_events = group_events_by_finding(&events);

    snapshot
        .get("findings")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .map(|finding| {
            let finding_id = get_str(&finding, "id").unwrap_or_default().to_string();
            let patch = patches
                .iter()
                .find(|patch| get_str(patch, "findingId") == Some(finding_id.as_str()));
            let status = historical_status(&finding, patch);
            serde_json::json!({
                "findingId": finding_id,
                "sessionId": session_id,
                "workspaceId": workspace_id,
                "domain": historical_domain(&finding),
                "severity": historical_severity(get_str(&finding, "severity")),
                "title": get_str(&finding, "message").unwrap_or_default(),
                "summary": get_str(&finding, "evidence").unwrap_or_else(|| get_str(&finding, "message").unwrap_or_default()),
                "status": status,
                "filePath": get_str(&finding, "filePath").unwrap_or_default(),
                "lineStart": finding.get("lineNumber").cloned().unwrap_or(Value::Null),
                "sourceOrigin": finding.get("origin").cloned().unwrap_or(Value::Null),
                "closedReason": historical_closed_reason(get_str(&finding, "status")),
                "patchId": patch.and_then(|item| item.get("id")).cloned().unwrap_or(Value::Null),
                "patchApplyStatus": historical_patch_apply_status(patch),
                "revalidationReportId": patch.and_then(|item| item.get("validationRunId")).cloned().unwrap_or(Value::Null),
                "revalidationVerdict": historical_revalidation_verdict(patch),
                "createdAt": finding.get("createdAt").cloned().unwrap_or(Value::from(0.0)),
                "updatedAt": patch.and_then(|item| item.get("updatedAt")).cloned()
                    .or_else(|| finding.get("verifiedAt").cloned())
                    .unwrap_or_else(|| finding.get("createdAt").cloned().unwrap_or(Value::from(0.0))),
                "resolvedAt": if finding_applied(get_str(&finding, "status")) {
                    patch.and_then(|item| item.get("updatedAt")).cloned()
                        .or_else(|| finding.get("verifiedAt").cloned())
                        .unwrap_or(Value::Null)
                } else { Value::Null },
                "resumeEligible": !terminal_historical_status(status),
                "timeline": grouped_events.get(&finding_id).cloned().unwrap_or_default(),
            })
        })
        .collect()
}

fn group_events_by_finding(events: &[Value]) -> HashMap<String, Vec<Value>> {
    let mut grouped: HashMap<String, Vec<Value>> = HashMap::new();
    for event in events {
        let finding_id = event
            .get("metadata")
            .and_then(Value::as_object)
            .and_then(|meta| meta.get("finding_id").or_else(|| meta.get("candidate_id")))
            .and_then(Value::as_str);
        let Some(finding_id) = finding_id else { continue };
        grouped.entry(finding_id.to_string()).or_default().push(serde_json::json!({
            "eventId": event.get("id").cloned().unwrap_or(Value::Null),
            "eventType": event.get("type").cloned().unwrap_or(Value::Null),
            "detail": event.get("detail").cloned().unwrap_or(Value::Null),
            "createdAt": event.get("timestamp").cloned().unwrap_or(Value::from(0.0)),
            "metadata": event.get("metadata").cloned().unwrap_or_else(|| serde_json::json!({})),
        }));
    }
    grouped
}

fn historical_domain(finding: &Value) -> &'static str {
    match (get_str(finding, "origin"), get_str(finding, "category")) {
        (Some("securityAuditor"), _) | (_, Some("security")) => "security",
        _ => "bug",
    }
}

fn historical_severity(severity: Option<&str>) -> &'static str {
    match severity {
        Some("critical") => "critical",
        Some("warning") => "medium",
        Some("suggestion") => "low",
        _ => "info",
    }
}

fn historical_status(finding: &Value, patch: Option<&Value>) -> &'static str {
    if let Some(patch) = patch {
        match (get_str(patch, "status"), get_str(patch, "validationStatus")) {
            (Some("applied"), Some("passed")) => return "fixed_verified",
            (Some("applied"), Some("failed")) => return "fix_failed",
            (Some("applied"), _) => return "patch_applied",
            (Some("rolled_back"), _) => return "rollback_applied",
            _ => {}
        }
    }
    match get_str(finding, "status") {
        Some("open") => "verified",
        Some("fix_applied") | Some("patch_applied") => "patch_applied",
        Some("patch_preparing") => "patch_preparing",
        Some("patch_ready") => "patch_prepared",
        Some("patch_applying") => "patch_reviewed",
        Some("patch_failed") => "fix_failed",
        Some("pr_opened") | Some("merged") | Some("closed") => "closed",
        Some("blocked") => "needs_manual_review",
        Some("dismissed") | Some("wont_fix") => "rejected",
        _ => "verified",
    }
}

fn historical_patch_apply_status(patch: Option<&Value>) -> Value {
    match patch.and_then(|item| get_str(item, "status")) {
        Some("applied") => Value::String("applied".to_string()),
        Some("apply_failed") => Value::String("failed".to_string()),
        Some("rolled_back") => Value::String("rolled_back".to_string()),
        Some(_) => Value::String("not_applied".to_string()),
        None => Value::Null,
    }
}

fn historical_revalidation_verdict(patch: Option<&Value>) -> Value {
    match (
        patch.and_then(|item| get_str(item, "status")),
        patch.and_then(|item| get_str(item, "validationStatus")),
    ) {
        (Some("applied"), Some("passed")) => Value::String("fixed_verified".to_string()),
        (Some("applied"), Some("failed")) | (Some("apply_failed"), Some("failed")) => {
            Value::String("fix_failed".to_string())
        }
        _ => Value::Null,
    }
}

fn historical_closed_reason(status: Option<&str>) -> Value {
    match status {
        Some("dismissed") => Value::String("dismissed".to_string()),
        Some("wont_fix") => Value::String("wont_fix".to_string()),
        Some("merged") => Value::String("merged".to_string()),
        Some("pr_opened") => Value::String("pr_opened".to_string()),
        Some("closed") => Value::String("closed".to_string()),
        _ => Value::Null,
    }
}

fn terminal_historical_status(status: &str) -> bool {
    matches!(status, "fixed_verified" | "closed" | "rejected")
}

fn finding_applied(status: Option<&str>) -> bool {
    matches!(status, Some("fix_applied") | Some("patch_applied") | Some("merged"))
}
