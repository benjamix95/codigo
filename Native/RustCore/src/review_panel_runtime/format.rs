use super::models::{ReviewPanelRuntimeEventEnvelope, ReviewPanelRuntimeStateSnapshot};
use super::state::replace_response;
use serde_json::Value;

pub fn apply_raw_event(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    event: &ReviewPanelRuntimeEventEnvelope,
    response_message_id: Option<&str>,
    timestamp: Option<f64>,
) {
    let event_type = event.event_type.as_deref().unwrap_or_default();
    let payload = &event.payload;
    let Some((section_title, line)) = formatted_raw_event(event_type, payload) else {
        return;
    };
    if section_title == "Response" {
        replace_response(state, activity_id, &line, response_message_id, timestamp);
    } else {
        append_section_line(state, activity_id, &section_title, &line);
    }
}

pub fn append_section_line(
    state: &mut ReviewPanelRuntimeStateSnapshot,
    activity_id: &str,
    section_title: &str,
    line: &str,
) {
    let trimmed_line = line.trim();
    if trimmed_line.is_empty() {
        return;
    }
    let Some(index) = state
        .chat_messages
        .iter()
        .position(|message| message.get("id").and_then(Value::as_str) == Some(activity_id))
    else {
        return;
    };

    let current = state.chat_messages[index]
        .get("content")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let separator = "\n---\n";
    let mut parts = current.split(separator);
    let mut log_part = parts.next().unwrap_or_default().to_string();
    let verdict_part = parts.collect::<Vec<_>>().join(separator);
    let heading = format!("### {section_title}");

    if is_duplicate_line(trimmed_line, section_title, &log_part) {
        return;
    }
    if !log_part.contains(&heading) {
        if !log_part.trim().is_empty() {
            log_part.push_str("\n\n");
        }
        log_part.push_str(&heading);
        log_part.push('\n');
        log_part.push_str(trimmed_line);
        log_part.push('\n');
    } else {
        log_part = insert_line_in_section(&log_part, &heading, trimmed_line);
    }

    let rebuilt = if verdict_part.trim().is_empty() {
        log_part.trim().to_string()
    } else {
        format!("{}{}{}", log_part.trim(), separator, verdict_part)
    };
    if let Some(object) = state.chat_messages[index].as_object_mut() {
        object.insert("content".to_string(), Value::String(rebuilt));
        object.insert("presentation".to_string(), Value::Null);
    }
}

fn formatted_raw_event(
    event_type: &str,
    payload: &std::collections::BTreeMap<String, String>,
) -> Option<(String, String)> {
    match event_type {
        "reasoning" => first_non_empty(payload, &["detail", "text", "delta", "content", "summary"])
            .map(|detail| ("Thinking".to_string(), detail)),
        "assistant_update" => first_non_empty(payload, &["output", "content", "text", "detail", "summary"])
            .map(|detail| ("Response".to_string(), detail)),
        "review-worker-plan" => {
            let description = first_non_empty(payload, &["description", "title"])
                .unwrap_or_else(|| "Planned worker".to_string());
            let severity = payload.get("severity").map(|item| format!("[{item}] ")).unwrap_or_default();
            let file_count = payload.get("fileCount").map(|item| format!(" ({item} files)")).unwrap_or_default();
            Some(("Planned Work".to_string(), format!("- [ ] {severity}{description}{file_count}")))
        }
        "review-fix-round" => Some((
            "Progress".to_string(),
            format!(
                "Round {}/{}",
                payload.get("round").cloned().unwrap_or_else(|| "?".to_string()),
                payload.get("maxRounds").cloned().unwrap_or_else(|| "?".to_string())
            ),
        )),
        "review-audit-tool" => Some((
            "Audit".to_string(),
            format!(
                "{}: {}",
                payload.get("tool").cloned().unwrap_or_else(|| "audit".to_string()),
                payload.get("detail").cloned().unwrap_or_else(|| "completed".to_string())
            ),
        )),
        "agent" => Some((
            "Activity".to_string(),
            format!(
                "{} — {}",
                payload
                    .get("title")
                    .cloned()
                    .or_else(|| payload.get("agent_name").cloned())
                    .unwrap_or_else(|| "agent".to_string()),
                payload
                    .get("detail")
                    .cloned()
                    .or_else(|| payload.get("status").cloned())
                    .unwrap_or_else(|| "updated".to_string())
            ),
        )),
        "tool_execution_error" | "tool_validation_error" => Some((
            "Activity".to_string(),
            format!(
                "Error: {}",
                payload
                    .get("detail")
                    .cloned()
                    .or_else(|| payload.get("title").cloned())
                    .unwrap_or_else(|| "Tool error".to_string())
            ),
        )),
        _ => Some((
            "Activity".to_string(),
            payload
                .get("detail")
                .cloned()
                .or_else(|| payload.get("title").cloned())
                .or_else(|| payload.get("summary").cloned())
                .or_else(|| payload.get("status").cloned())
                .or_else(|| payload.get("tool").cloned())
                .or_else(|| payload.get("type").cloned())
                .map(|detail| format!("{event_type}: {detail}"))
                .unwrap_or_else(|| event_type.to_string()),
        )),
    }
}

fn first_non_empty(
    payload: &std::collections::BTreeMap<String, String>,
    keys: &[&str],
) -> Option<String> {
    keys.iter()
        .filter_map(|key| payload.get(*key))
        .map(|value| value.trim())
        .find(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn insert_line_in_section(log_part: &str, heading: &str, line: &str) -> String {
    let Some(start) = log_part.find(heading) else {
        return format!("{log_part}\n{line}\n");
    };
    let after_heading = &log_part[start + heading.len()..];
    if let Some(next) = after_heading.find("\n### ") {
        let insert_point = start + heading.len() + next;
        let mut result = log_part[..insert_point].to_string();
        if !result.ends_with('\n') {
            result.push('\n');
        }
        result.push_str(line);
        result.push('\n');
        result.push_str(&log_part[insert_point..]);
        return result;
    }
    let mut result = log_part.to_string();
    if !result.ends_with('\n') {
        result.push('\n');
    }
    result.push_str(line);
    result.push('\n');
    result
}

fn is_duplicate_line(line: &str, section_title: &str, log_part: &str) -> bool {
    let heading = format!("### {section_title}");
    let Some(start) = log_part.find(&heading) else {
        return false;
    };
    let after_heading = &log_part[start + heading.len()..];
    let section_content = if let Some(next) = after_heading.find("\n### ") {
        &after_heading[..next]
    } else {
        after_heading
    };
    section_content.contains(line)
}
