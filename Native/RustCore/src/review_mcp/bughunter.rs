use super::models::{ReviewMCPToolRequest, ReviewMCPToolResponse};

pub fn handle_bughunter_tool(request: ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    match request.tool_name.as_str() {
        "bughunter_start" => bughunter_start(&request),
        "bughunter_commit_window" => bughunter_commit_window(&request),
        "bughunter_status" => bughunter_status(&request),
        "bughunter_findings" => bughunter_findings(&request),
        "bughunter_run_history" => bughunter_history(&request),
        "bughunter_explain_cluster" => bughunter_cluster(&request),
        "bughunter_cancel_run" | "bughunter_autofix_preview" | "bughunter_autofix_apply"
        | "bughunter_autofix_commit" | "bughunter_install_hook" | "bughunter_uninstall_hook" => {
            queue_bughunter_action(&request)
        }
        _ => ReviewMCPToolResponse::err(format!("Unknown bugHunter tool: {}", request.tool_name)),
    }
}

fn bughunter_start(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let source_kind = request.args.get("source_kind").map(|value| value.trim().to_lowercase()).filter(|value| !value.is_empty()).unwrap_or_else(|| "uncommitted".to_string());
    if !matches!(source_kind.as_str(), "uncommitted" | "commit" | "commit_window" | "branch_window") {
        return ReviewMCPToolResponse::err(format!("Error: invalid source_kind '{}'", source_kind));
    }
    let git_root = request.args.get("git_root").map(|value| value.trim()).unwrap_or("");
    if source_kind != "uncommitted" && git_root.is_empty() {
        return ReviewMCPToolResponse::err("Error: 'git_root' is required for this BugHunter scope");
    }
    ReviewMCPToolResponse::ok(format!("OK — bugHunter start queued (run_id=generated, source_kind={source_kind})"))
}

fn bughunter_commit_window(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let git_root = request.args.get("git_root").map(|value| value.trim()).unwrap_or("");
    let primary_commit = request.args.get("primary_commit").map(|value| value.trim()).unwrap_or("");
    if git_root.is_empty() || primary_commit.is_empty() {
        return ReviewMCPToolResponse::err("Error: 'git_root' and 'primary_commit' are required");
    }
    ReviewMCPToolResponse::ok("OK — bugHunter start queued (commit_window)".to_string())
}

fn bughunter_status(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let Some(snapshot) = request.active_bughunter_snapshot.as_ref() else {
        return ReviewMCPToolResponse::ok("No BugHunter run found.");
    };
    let mut lines = vec![
        format!("run_id: {}", snapshot.run_id),
        format!("status: {}", snapshot.status),
        format!("source_kind: {}", snapshot.source_kind),
        format!("trigger_kind: {}", snapshot.trigger_kind),
        format!("git_root: {}", snapshot.git_root),
    ];
    if let Some(review_session_id) = &snapshot.review_session_id {
        lines.push(format!("review_session_id: {}", review_session_id));
    }
    if let Some(branch_name) = &snapshot.branch_name {
        lines.push(format!("branch: {}", branch_name));
    }
    if let Some(primary_commit) = &snapshot.primary_commit {
        lines.push(format!("primary_commit: {}", primary_commit));
    }
    if !snapshot.related_commits.is_empty() {
        lines.push(format!("related_commits: {}", snapshot.related_commits.join(",")));
    }
    if let Some(message) = &snapshot.last_message {
        lines.push(format!("message: {}", message));
    }
    lines.push(format!("verified_findings_count: {}", snapshot.verified_findings_count));
    lines.push(format!("candidate_findings_count: {}", snapshot.candidate_findings_count));
    if let Some(verdict) = &snapshot.last_revalidation_verdict {
        lines.push(format!("last_revalidation_verdict: {}", verdict));
    }
    if let Some(ready) = snapshot.security_gate_ready {
        lines.push(format!("security_gate_ready_cached: {}", if ready { "true" } else { "false" }));
    }
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn bughunter_findings(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if request.bughunter_findings_payload.is_empty() {
        return ReviewMCPToolResponse::ok("No BugHunter findings match the query.");
    }
    let lines = request.bughunter_findings_payload.iter().enumerate().map(|(index, finding)| {
        let message = finding.get("message").or_else(|| finding.get("message_summary")).cloned().unwrap_or_else(|| "n/a".to_string());
        let file = finding.get("file_path").or_else(|| finding.get("file_label")).cloned().unwrap_or_else(|| "redacted".to_string());
        let line = finding.get("line_number").map(|value| format!(":{value}")).unwrap_or_default();
        let duplicate = finding.get("possible_duplicate_of").map(|value| format!(", duplicate_of: {value}")).unwrap_or_default();
        let stale = finding.get("stale_status").map(|value| format!(", stale: {value}")).unwrap_or_default();
        format!(
            "[{}] [{}] {}{} — {} (domain: {}, status: {}{}{}, id: {}))",
            index + 1,
            finding.get("severity").cloned().unwrap_or_else(|| "?".to_string()),
            file,
            line,
            message,
            finding.get("domain").cloned().unwrap_or_else(|| "bug".to_string()),
            finding.get("status").cloned().unwrap_or_else(|| "?".to_string()),
            duplicate,
            stale,
            finding.get("id").cloned().unwrap_or_else(|| "?".to_string())
        )
    }).collect::<Vec<_>>();
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn bughunter_history(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if request.bughunter_snapshots.is_empty() {
        return ReviewMCPToolResponse::ok("No BugHunter runs found.");
    }
    let lines = request.bughunter_snapshots.iter().map(|snapshot| {
        format!(
            "{} | {} | {} | review={} | message={}",
            snapshot.run_id,
            snapshot.status,
            snapshot.source_kind,
            snapshot.review_session_id.clone().unwrap_or_else(|| "n/a".to_string()),
            snapshot.last_message.clone().unwrap_or_else(|| "n/a".to_string()),
        )
    }).collect::<Vec<_>>();
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn bughunter_cluster(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let Some(payload) = &request.bughunter_cluster_payload else {
        return ReviewMCPToolResponse::ok("No BugHunter cluster available.");
    };
    let lines = vec![
        format!("cluster_title: {}", payload.get("cluster_title").cloned().unwrap_or_else(|| "n/a".to_string())),
        format!("cluster_size: {}", payload.get("cluster_size").cloned().unwrap_or_else(|| "0".to_string())),
        format!("files: {}", payload.get("files").cloned().unwrap_or_default()),
        format!("avg_confidence: {}", payload.get("avg_confidence").cloned().unwrap_or_else(|| "0.00".to_string())),
        format!("primary_risk: {}", payload.get("primary_risk").cloned().unwrap_or_else(|| "unknown".to_string())),
    ];
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn queue_bughunter_action(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let run_id = request.args.get("run_id").map(|value| value.trim()).unwrap_or("");
    if run_id.is_empty() {
        return ReviewMCPToolResponse::err("Error: 'run_id' is required");
    }
    if request.active_bughunter_snapshot.is_none() {
        return ReviewMCPToolResponse::err(format!("Error: run_id '{}' was not found", run_id));
    }
    ReviewMCPToolResponse::ok(format!(
        "OK — bugHunter command queued (action={}, run_id={})",
        request.tool_name.trim_start_matches("bughunter_"),
        run_id
    ))
}
