use super::models::{
    find_patch, get_arg, payload_line_map, trimmed_arg, ReviewMCPToolRequest, ReviewMCPToolResponse,
};

pub fn handle_review_tool(request: ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    match request.tool_name.as_str() {
        "review_start" => review_start(&request),
        "review_status" => review_status(&request),
        "review_findings" => review_findings(&request),
        "review_list_sessions" => review_list_sessions(&request),
        "review_get_outcome" => review_get_outcome(&request),
        "review_apply_fix"
        | "review_dismiss"
        | "review_comment"
        | "review_configure"
        | "review_verify_finding"
        | "review_prepare_patch"
        | "review_apply_patch"
        | "review_verify_patch"
        | "review_revalidate_finding"
        | "review_rollback_patch"
        | "review_close_finding"
        | "review_open_pr"
        | "review_merge_pr"
        | "review_resolve_conflicts" => queueable_review_action(&request),
        _ => ReviewMCPToolResponse::err(format!("Unknown code review tool: {}", request.tool_name)),
    }
}

fn review_start(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let scope = normalized_scope(get_arg(&request.args, "scope"));
    if !matches!(
        scope.as_str(),
        "uncommitted" | "staged" | "against_ref" | "workspace" | "codebase"
    ) {
        return ReviewMCPToolResponse::err(format!(
            "Error: invalid scope '{}'. Use: uncommitted, staged, against_ref, workspace, codebase",
            scope
        ));
    }
    if scope == "against_ref" && trimmed_arg(&request.args, "ref").is_empty() {
        return ReviewMCPToolResponse::err(
            "Error: 'ref' parameter is required when scope=against_ref",
        );
    }
    if let Some(session_id) = request
        .args
        .get("session_id")
        .cloned()
        .or_else(|| request.args.get("sessionId").cloned())
    {
        if !valid_session_id(&session_id) {
            return ReviewMCPToolResponse::err(
                "Error: invalid session_id. Use only letters, numbers, hyphen, or underscore",
            );
        }
    }
    if let Some(value) = request.args.get("analysis_only") {
        let normalized = value.trim().to_lowercase();
        if !normalized.is_empty()
            && !matches!(
                normalized.as_str(),
                "1" | "0" | "true" | "false" | "yes" | "no" | "y" | "n"
            )
        {
            return ReviewMCPToolResponse::err("Error: analysis_only must be a boolean value");
        }
    }
    if let Some(value) = request
        .args
        .get("max_workers")
        .filter(|value| !value.trim().is_empty())
    {
        match value.trim().parse::<i32>() {
            Ok(value) if (1..=12).contains(&value) => {}
            _ => return ReviewMCPToolResponse::err("Error: max_workers must be 1-12"),
        }
    }
    if let Some(value) = request
        .args
        .get("max_rounds")
        .filter(|value| !value.trim().is_empty())
    {
        match value.trim().parse::<i32>() {
            Ok(value) if (1..=10).contains(&value) => {}
            _ => return ReviewMCPToolResponse::err("Error: max_rounds must be 1-10"),
        }
    }
    ReviewMCPToolResponse::ok(format!(
        "OK — code review start queued (session_id={}, scope={})",
        request
            .args
            .get("session_id")
            .or_else(|| request.args.get("sessionId"))
            .map(String::as_str)
            .unwrap_or("generated"),
        scope
    ))
}

fn review_status(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if let Some(payload) = &request.review_status_payload {
        let mut lines = payload_line_map(
            payload,
            &[
                "session_id",
                "phase",
                "stage",
                "summary",
                "findings_total",
                "candidates_total",
                "verified_projection_findings",
                "verified_projection_candidates",
                "verified_projection_duplicates",
                "verified_projection_stale_candidates",
                "security_gate_ready",
                "security_gate_summary",
            ],
        );
        if lines.is_empty() {
            lines.push("No active review session.".to_string());
        }
        return ReviewMCPToolResponse::ok(lines.join("\n"));
    }
    ReviewMCPToolResponse::ok("No active review session.")
}

fn review_findings(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if let Some(message) = validate_filters(&request.args) {
        return ReviewMCPToolResponse::err(message);
    }
    if request.review_findings_payload.is_empty() {
        return ReviewMCPToolResponse::ok("No findings match the query.");
    }
    let lines = request
        .review_findings_payload
        .iter()
        .enumerate()
        .map(|(index, finding)| {
            let message = finding.get("message").or_else(|| finding.get("message_summary")).cloned().unwrap_or_else(|| "Redacted finding details".to_string());
            let file = finding.get("file_path").or_else(|| finding.get("file_label")).cloned().unwrap_or_else(|| "redacted-file".to_string());
            let line = finding.get("line_number").map(|value| format!(":{value}")).unwrap_or_default();
            let origin = finding.get("origin").cloned().unwrap_or_else(|| "reviewer".to_string());
            let category = finding.get("category").cloned().unwrap_or_else(|| "unknown".to_string());
            let status = finding.get("status").cloned().unwrap_or_else(|| "open".to_string());
            let kind = finding.get("kind").cloned().unwrap_or_else(|| "verified".to_string());
            let domain = finding.get("domain").cloned().unwrap_or_else(|| "bug".to_string());
            let duplicate = finding.get("possible_duplicate_of").map(|value| format!(", duplicate_of: {value}")).unwrap_or_default();
            let stale = finding.get("stale_status").map(|value| format!(", stale: {value}")).unwrap_or_default();
            format!(
                "[{}] [{}] [{}] {}{} — {} (domain: {}, origin: {}, category: {}, status: {}{}{}, id: {}))",
                index + 1,
                kind,
                finding.get("severity").cloned().unwrap_or_else(|| "?".to_string()),
                file,
                line,
                message,
                domain,
                origin,
                category,
                status,
                duplicate,
                stale,
                finding.get("id").cloned().unwrap_or_else(|| "?".to_string())
            )
        })
        .collect::<Vec<_>>();
    ReviewMCPToolResponse::ok(format!(
        "Findings ({}):\n{}",
        request.review_findings_payload.len(),
        lines.join("\n")
    ))
}

fn review_list_sessions(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    if request.review_snapshots.is_empty() {
        return ReviewMCPToolResponse::ok("No review sessions found.");
    }
    let lines = request
        .review_snapshots
        .iter()
        .map(|snapshot| {
            format!(
                "{} | phase={} | stage={} | scope={} | findings={}",
                snapshot.session_id,
                snapshot.phase,
                snapshot.stage,
                snapshot
                    .scope_type
                    .clone()
                    .unwrap_or_else(|| "unknown".to_string()),
                snapshot.findings_count
            )
        })
        .collect::<Vec<_>>();
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn review_get_outcome(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let Some(payload) = &request.review_outcome_payload else {
        return ReviewMCPToolResponse::err("Error: unable to load the requested review session");
    };
    let lines = payload_line_map(
        payload,
        &[
            "summary",
            "verified_findings",
            "false_positives",
            "patches_ready",
            "patches_applied",
            "prs_opened",
            "merged_patches",
            "conflicts_detected",
            "manual_action_required",
            "tests_status",
        ],
    );
    ReviewMCPToolResponse::ok(lines.join("\n"))
}

fn queueable_review_action(request: &ReviewMCPToolRequest) -> ReviewMCPToolResponse {
    let primary = trimmed_arg(&request.args, "session_id");
    let session_id = if !primary.is_empty() {
        Some(primary)
    } else {
        let alt = trimmed_arg(&request.args, "sessionId");
        if alt.is_empty() {
            None
        } else {
            Some(alt)
        }
    };
    let Some(session_id) = session_id else {
        return ReviewMCPToolResponse::err("Error: 'session_id' parameter is required");
    };
    let Some(snapshot) = request.active_review_snapshot.as_ref() else {
        return ReviewMCPToolResponse::err(format!(
            "Error: session_id '{}' was not found",
            session_id
        ));
    };
    let finding_id = trimmed_arg(&request.args, "finding_id");
    let requires_finding = request.tool_name != "review_configure";
    if requires_finding && finding_id.is_empty() {
        return ReviewMCPToolResponse::err("Error: 'finding_id' parameter is required");
    }
    if !finding_id.is_empty()
        && !snapshot.finding_ids.iter().any(|id| id == &finding_id)
        && !snapshot.candidate_ids.iter().any(|id| id == &finding_id)
    {
        return ReviewMCPToolResponse::err(format!(
            "Error: finding_id '{}' does not belong to session_id '{}'",
            finding_id, session_id
        ));
    }
    if request.tool_name == "review_apply_patch" {
        let Some(patch) = find_patch(snapshot, &finding_id) else {
            return ReviewMCPToolResponse::err(
                "Error: no prepared patch artifact found. Run review_prepare_patch first.",
            );
        };
        if patch.verify_status != "verified" {
            return ReviewMCPToolResponse::err("Error: patch artifact is not verified. Run review_prepare_patch or review_verify_patch first.");
        }
    }
    ReviewMCPToolResponse::ok(format!(
        "OK — review command queued, action={}, session_id={}",
        normalized_action(&request.tool_name),
        session_id
    ))
}

fn validate_filters(args: &std::collections::HashMap<String, String>) -> Option<String> {
    let severity = trimmed_arg(args, "severity").to_lowercase();
    if !severity.is_empty()
        && !matches!(
            severity.as_str(),
            "critical" | "warning" | "suggestion" | "info"
        )
    {
        return Some(format!(
            "Error: invalid severity '{}'. Use: critical, warning, suggestion, info",
            severity
        ));
    }
    let status = trimmed_arg(args, "status").to_lowercase();
    if !status.is_empty()
        && !matches!(
            status.as_str(),
            "open"
                | "fix_applied"
                | "patch_preparing"
                | "patch_ready"
                | "patch_applying"
                | "patch_applied"
                | "patch_failed"
                | "pr_opened"
                | "merged"
                | "blocked"
                | "dismissed"
                | "wont_fix"
                | "new"
                | "verifying"
                | "verified"
                | "rejected_false_positive"
                | "inconclusive"
        )
    {
        return Some(format!(
            "Error: invalid status '{}' for code review items",
            status
        ));
    }
    let origin = trimmed_arg(args, "origin");
    if !origin.is_empty()
        && !matches!(
            origin.as_str(),
            "reviewer" | "bugHunter" | "securityAuditor" | "audit_tool"
        )
    {
        return Some(format!(
            "Error: invalid origin '{}'. Use: reviewer, bugHunter, securityAuditor, audit_tool",
            origin
        ));
    }
    let category = trimmed_arg(args, "category").to_lowercase();
    if !category.is_empty()
        && !matches!(
            category.as_str(),
            "correctness"
                | "regression"
                | "concurrency"
                | "security"
                | "tests"
                | "maintainability"
                | "performance"
                | "other"
        )
    {
        return Some(format!("Error: invalid category '{}'. Use: correctness, regression, concurrency, security, tests, maintainability, performance, other", category));
    }
    None
}

fn valid_session_id(session_id: &str) -> bool {
    let trimmed = session_id.trim();
    let mut chars = trimmed.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    first.is_ascii_alphanumeric()
        && trimmed.len() <= 128
        && chars.all(|ch| ch.is_ascii_alphanumeric() || ch == '-' || ch == '_')
}

fn normalized_scope(raw: &str) -> String {
    let trimmed = raw.trim().to_lowercase();
    if trimmed.is_empty() {
        "uncommitted".to_string()
    } else {
        trimmed
    }
}

fn normalized_action(tool_name: &str) -> &str {
    match tool_name {
        "review_apply_fix" => "apply_fix",
        "review_dismiss" => "dismiss",
        "review_comment" => "comment",
        "review_configure" => "configure",
        "review_verify_finding" => "verify_finding",
        "review_prepare_patch" => "prepare_patch",
        "review_apply_patch" => "apply_patch",
        "review_verify_patch" => "verify_patch",
        "review_revalidate_finding" => "revalidate_finding",
        "review_rollback_patch" => "rollback_patch",
        "review_close_finding" => "close_finding",
        "review_open_pr" => "open_pr",
        "review_merge_pr" => "merge_pr",
        "review_resolve_conflicts" => "resolve_conflicts",
        _ => "unknown",
    }
}
