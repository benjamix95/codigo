use super::models::{payload_line_map, ReviewMCPToolRequest, ReviewMCPToolResponse};
use super::review::handle_review_tool;

pub fn handle_security_tool(request: ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    match request.tool_name.as_str() {
        "security_start" => security_start(&request),
        "security_status" => security_status(&request),
        "security_findings" => security_findings(&request),
        "security_verify_finding"
        | "security_prepare_patch"
        | "security_apply_patch"
        | "security_verify_patch"
        | "security_revalidate_finding"
        | "security_rollback_patch"
        | "security_close_finding" => ReviewMCPToolResponse::ok(format!(
            "OK — security command queued, action={}",
            request.tool_name.trim_start_matches("security_")
        )),
        _ => handle_review_tool(request),
    }
}

fn security_start(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let Some(gate) = request.security_gate_payload.as_ref() else {
        return ReviewMCPToolResponse::err("Error: security gate not ready. security_gate=blocked, no verified bughunter baseline is available");
    };
    if gate.get("ready").map(String::as_str) != Some("true") {
        let summary = gate.get("summary").cloned().unwrap_or_else(|| {
            "security_gate=blocked, no verified bughunter baseline is available".to_string()
        });
        return ReviewMCPToolResponse::err(format!("Error: security gate not ready. {summary}"));
    }
    ReviewMCPToolResponse::ok("OK — code review start queued (security workflow)")
}

fn security_status(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let base = request
        .review_status_payload
        .as_ref()
        .map(|payload| {
            payload_line_map(payload, &["session_id", "phase", "stage", "summary"]).join("\n")
        })
        .unwrap_or_else(|| "No active review session.".to_string());
    let ready = request
        .security_gate_payload
        .as_ref()
        .and_then(|payload| payload.get("ready"))
        .cloned()
        .unwrap_or_else(|| "false".to_string());
    let summary = request
        .security_gate_payload
        .as_ref()
        .and_then(|payload| payload.get("summary"))
        .cloned()
        .unwrap_or_else(|| {
            "security_gate=blocked, no verified bughunter baseline is available".to_string()
        });
    ReviewMCPToolResponse::ok(format!(
        "{base}\nsecurity_gate_ready: {ready}\nsecurity_gate_summary: {summary}"
    ))
}

fn security_findings(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if request.review_findings_payload.is_empty() {
        return ReviewMCPToolResponse::ok("No security findings match the query.");
    }
    let lines = request
        .review_findings_payload
        .iter()
        .enumerate()
        .map(|(index, finding)| {
            let message = finding
                .get("message")
                .or_else(|| finding.get("message_summary"))
                .cloned()
                .unwrap_or_else(|| "n/a".to_string());
            let file = finding
                .get("file_path")
                .or_else(|| finding.get("file_label"))
                .cloned()
                .unwrap_or_else(|| "redacted".to_string());
            let line = finding
                .get("line_number")
                .map(|value| format!(":{value}"))
                .unwrap_or_default();
            let stale = finding
                .get("stale_status")
                .map(|value| format!(", stale: {value}"))
                .unwrap_or_default();
            format!(
                "[{}] [{}] {}{} — {} (domain: security, status: {}{}, id: {}))",
                index + 1,
                finding
                    .get("severity")
                    .cloned()
                    .unwrap_or_else(|| "?".to_string()),
                file,
                line,
                message,
                finding
                    .get("status")
                    .cloned()
                    .unwrap_or_else(|| "?".to_string()),
                stale,
                finding
                    .get("id")
                    .cloned()
                    .unwrap_or_else(|| "?".to_string())
            )
        })
        .collect::<Vec<_>>();
    ReviewMCPToolResponse::ok(lines.join("\n"))
}
