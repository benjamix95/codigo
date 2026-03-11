use super::models::{ReviewCommandMutationRequest, ReviewCommandMutationResponse};
use serde_json::{json, Value};

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
    let timestamp = request
        .snapshot
        .get("lastUpdatedAt")
        .and_then(Value::as_str)
        .unwrap_or("1970-01-01T00:00:00Z")
        .to_string();
    let mut findings = findings.clone();
    let mut events = events.clone();

    let result = match request.action.as_str() {
        "apply_fix" => apply_fix(&mut findings, &mut events, &request.payload, &timestamp),
        "dismiss" => dismiss(&mut findings, &mut events, &request.payload, &timestamp),
        "comment" => comment(&mut findings, &mut events, &request.payload, &timestamp),
        "close_finding" => close_finding(
            &mut findings,
            &mut events,
            &patches,
            &request.payload,
            &timestamp,
        ),
        _ => return ReviewCommandMutationResponse::error("Unsupported snapshot mutation"),
    };
    if let Err(error) = result {
        return error;
    }

    ReviewCommandMutationResponse::success(findings, events)
}

fn apply_fix(
    findings: &mut [Value],
    events: &mut Vec<Value>,
    payload: &std::collections::HashMap<String, String>,
    timestamp: &str,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let finding = find_finding(findings, &finding_id)?;
    finding["status"] = Value::String("fix_applied".to_string());
    events.push(event(
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
    timestamp: &str,
) -> Result<(), ReviewCommandMutationResponse> {
    let finding_id = required(payload, "finding_id")?;
    let reason = payload.get("reason").map(|v| v.trim()).filter(|v| !v.is_empty()).unwrap_or("dismissed");
    let finding = find_finding(findings, &finding_id)?;
    finding["status"] = Value::String(if reason.eq_ignore_ascii_case("wont_fix") {
        "wont_fix".to_string()
    } else {
        "dismissed".to_string()
    });
    events.push(event(
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
    timestamp: &str,
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
    events.push(event(
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
    timestamp: &str,
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
    events.push(event(
        "outcome_published",
        format!("Finding {} closed", finding_id),
        json!({ "finding_id": finding_id, "reason": reason }),
        timestamp,
    ));
    Ok(())
}

fn required(
    payload: &std::collections::HashMap<String, String>,
    key: &str,
) -> Result<String, ReviewCommandMutationResponse> {
    payload
        .get(key)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or_else(|| ReviewCommandMutationResponse::error(format!("Missing {}", key)))
}

fn find_finding<'a>(
    findings: &'a mut [Value],
    finding_id: &str,
) -> Result<&'a mut Value, ReviewCommandMutationResponse> {
    findings
        .iter_mut()
        .find(|finding| finding.get("id").and_then(Value::as_str) == Some(finding_id))
        .ok_or_else(|| ReviewCommandMutationResponse::error("Finding not found"))
}

fn find_patch<'a>(patches: &'a [Value], finding_id: &str) -> Option<&'a Value> {
    patches
        .iter()
        .find(|patch| patch.get("findingId").and_then(Value::as_str) == Some(finding_id))
}

fn event(event_type: &str, detail: String, metadata: Value, timestamp: &str) -> Value {
    json!({
        "id": format!("command-event-{}-{}", event_type, timestamp),
        "type": event_type,
        "timestamp": timestamp,
        "detail": detail,
        "metadata": metadata,
    })
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
}
