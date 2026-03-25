use crate::shared_review_state as state;
use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use solocode_rust_core::review_diff::{render_summary, ReviewDiffSummaryRequest};
use solocode_rust_core::review_mcp::models::{ReviewMCPCommandQueueRequest, ReviewMCPToolRequest};
use solocode_rust_core::review_mcp::{
    enqueue_bughunter_command, enqueue_review_command, handle_bughunter_tool, handle_review_tool,
    handle_security_tool,
};
use std::collections::{BTreeMap, HashMap};
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn handle(
    name: &str,
    _workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    if name.starts_with("coderide_review_") {
        return Some(handle_review(name, arguments));
    }
    if name.starts_with("coderide_security_") {
        return Some(handle_security(name, arguments));
    }
    if name.starts_with("coderide_bughunter_") {
        return Some(handle_bughunter(name, arguments));
    }
    None
}

fn handle_review(name: &str, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let raw_args = as_string_args(arguments);
    if name == "coderide_review_preview_patch" {
        return preview_patch(&raw_args);
    }
    if name == "coderide_review_diff_summary" {
        return diff_summary(&raw_args);
    }
    let mut args = raw_args;
    if name == "coderide_review_start" && !args.contains_key("session_id") {
        args.insert("session_id".to_string(), format!("review-{}", uuid_like()));
    }
    let request = build_review_request(name, &args);
    let response = handle_review_tool(request);
    if response.is_error {
        return CallToolResult::error(response.message);
    }
    if should_enqueue_review_action(name) {
        let commands = state::read_review_commands();
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: if name == "coderide_review_start" {
                "enqueue_unique_review_start".to_string()
            } else {
                "enqueue".to_string()
            },
            queue_kind: "review".to_string(),
            commands,
            command_id: None,
            action: Some(review_action(name).to_string()),
            session_id: args
                .get("session_id")
                .or_else(|| args.get("sessionId"))
                .cloned(),
            run_id: None,
            conversation_id: args
                .get("conversation_id")
                .or_else(|| args.get("conversationId"))
                .cloned(),
            status: None,
            result_message: None,
            now_reference_seconds: state::reference_seconds_now(),
            payload: args.clone(),
        };
        let queued = enqueue_review_command(request);
        if let Err(e) = state::write_review_commands(&queued.commands) {
            eprintln!("[review_tools] CRITICAL: failed to persist review commands: {e}");
            return CallToolResult::error(format!("Failed to queue review command: {e}"));
        }
    }
    CallToolResult::text(response.message)
}

fn handle_security(name: &str, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut args = as_string_args(arguments);
    if name == "coderide_security_start" && !args.contains_key("session_id") {
        args.insert("session_id".to_string(), format!("review-{}", uuid_like()));
    }
    let request = build_review_request(name, &args);
    let response = handle_security_tool(request);
    if response.is_error {
        return CallToolResult::error(response.message);
    }
    if name != "coderide_security_status"
        && name != "coderide_security_findings"
        && name != "coderide_security_preview_patch"
    {
        let commands = state::read_review_commands();
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: "enqueue".to_string(),
            queue_kind: "review".to_string(),
            commands,
            command_id: None,
            action: Some(security_action(name).to_string()),
            session_id: args
                .get("session_id")
                .or_else(|| args.get("sessionId"))
                .cloned(),
            run_id: None,
            conversation_id: args
                .get("conversation_id")
                .or_else(|| args.get("conversationId"))
                .cloned(),
            status: None,
            result_message: None,
            now_reference_seconds: state::reference_seconds_now(),
            payload: security_payload(name, &args),
        };
        let queued = enqueue_review_command(request);
        if let Err(e) = state::write_review_commands(&queued.commands) {
            eprintln!("[review_tools] CRITICAL: failed to persist security commands: {e}");
            return CallToolResult::error(format!("Failed to queue security command: {e}"));
        }
    }
    CallToolResult::text(response.message)
}

fn handle_bughunter(name: &str, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut args = as_string_args(arguments);
    if name == "coderide_bughunter_start" {
        let run_id = format!("bughunter-{}", uuid_like());
        args.insert("run_id".to_string(), run_id.clone());
        let commands = state::read_bughunter_commands();
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: "enqueue".to_string(),
            queue_kind: "bughunter".to_string(),
            commands,
            command_id: None,
            action: Some("start".to_string()),
            session_id: None,
            run_id: Some(run_id.clone()),
            conversation_id: args
                .get("conversation_id")
                .or_else(|| args.get("conversationId"))
                .cloned(),
            status: None,
            result_message: None,
            now_reference_seconds: state::reference_seconds_now(),
            payload: args.clone(),
        };
        let queued = enqueue_bughunter_command(request);
        if let Err(e) = state::write_bughunter_commands(&queued.commands) {
            eprintln!("[review_tools] CRITICAL: failed to persist bughunter start: {e}");
            return CallToolResult::error(format!("Failed to queue bughunter start: {e}"));
        }
        return CallToolResult::text(format!(
            "OK — bugHunter start queued (run_id={}, source_kind={})",
            run_id,
            args.get("source_kind")
                .cloned()
                .unwrap_or_else(|| "uncommitted".to_string())
        ));
    }
    let request = build_review_request(name, &args);
    let response = handle_bughunter_tool(request);
    if response.is_error {
        return CallToolResult::error(response.message);
    }
    if should_enqueue_bughunter_action(name) {
        let commands = state::read_bughunter_commands();
        let request = ReviewMCPCommandQueueRequest {
            schema_version: 1,
            operation: "enqueue".to_string(),
            queue_kind: "bughunter".to_string(),
            commands,
            command_id: None,
            action: Some(name.trim_start_matches("coderide_bughunter_").to_string()),
            session_id: None,
            run_id: args.get("run_id").cloned(),
            conversation_id: args
                .get("conversation_id")
                .or_else(|| args.get("conversationId"))
                .cloned(),
            status: None,
            result_message: None,
            now_reference_seconds: state::reference_seconds_now(),
            payload: args.clone(),
        };
        let queued = enqueue_bughunter_command(request);
        if let Err(e) = state::write_bughunter_commands(&queued.commands) {
            eprintln!("[review_tools] CRITICAL: failed to persist bughunter command: {e}");
            return CallToolResult::error(format!("Failed to queue bughunter command: {e}"));
        }
    }
    CallToolResult::text(response.message)
}

fn build_review_request(name: &str, args: &HashMap<String, String>) -> ReviewMCPToolRequest {
    let review_snapshots = state::read_review_snapshots();
    let bughunter_snapshots = state::read_bughunter_snapshots();
    let active_review = resolve_active_review_snapshot(&review_snapshots, args);
    let active_bughunter = resolve_active_bughunter_snapshot(&bughunter_snapshots, args);
    ReviewMCPToolRequest {
        schema_version: 1,
        tool_name: name.trim_start_matches("coderide_").to_string(),
        args: args.clone(),
        review_snapshots: review_snapshots
            .iter()
            .filter_map(state::make_review_snapshot_record)
            .collect(),
        active_review_snapshot: active_review
            .as_ref()
            .and_then(state::make_review_snapshot_record),
        review_findings_payload: active_review
            .as_ref()
            .map(|snapshot| findings_payload(snapshot, args))
            .unwrap_or_default(),
        review_status_payload: active_review
            .as_ref()
            .map(status_payload)
            .or_else(|| bughunter_status_payload_from_review(&bughunter_snapshots)),
        review_outcome_payload: active_review.as_ref().map(outcome_payload),
        bughunter_snapshots: bughunter_snapshots
            .iter()
            .filter_map(state::make_bughunter_snapshot_record)
            .collect(),
        active_bughunter_snapshot: active_bughunter
            .as_ref()
            .and_then(state::make_bughunter_snapshot_record),
        bughunter_findings_payload: active_bughunter
            .as_ref()
            .and_then(|run| run.get("reviewSessionId").and_then(Value::as_str))
            .and_then(|session_id| state::read_review_snapshot(session_id))
            .map(|snapshot| bughunter_findings_payload(&snapshot, args))
            .unwrap_or_default(),
        bughunter_cluster_payload: active_bughunter
            .as_ref()
            .and_then(|run| run.get("reviewSessionId").and_then(Value::as_str))
            .and_then(|session_id| state::read_review_snapshot(session_id))
            .and_then(|snapshot| cluster_payload(&snapshot)),
        security_gate_payload: active_review.as_ref().map(security_gate_payload),
    }
}

fn resolve_active_review_snapshot(
    snapshots: &[Value],
    args: &HashMap<String, String>,
) -> Option<Value> {
    if let Some(session_id) = args.get("session_id").or_else(|| args.get("sessionId")) {
        return snapshots
            .iter()
            .find(|snapshot| {
                snapshot.get("sessionId").and_then(Value::as_str) == Some(session_id.as_str())
            })
            .cloned();
    }
    snapshots
        .iter()
        .filter(|snapshot| snapshot.get("phase").and_then(Value::as_str) != Some("completed"))
        .max_by_key(|snapshot| {
            snapshot
                .get("lastUpdatedAt")
                .and_then(Value::as_str)
                .unwrap_or("")
        })
        .cloned()
        .or_else(|| {
            snapshots
                .iter()
                .max_by_key(|snapshot| {
                    snapshot
                        .get("lastUpdatedAt")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                })
                .cloned()
        })
}

fn resolve_active_bughunter_snapshot(
    snapshots: &[Value],
    args: &HashMap<String, String>,
) -> Option<Value> {
    if let Some(run_id) = args.get("run_id") {
        return snapshots
            .iter()
            .find(|snapshot| snapshot.get("runId").and_then(Value::as_str) == Some(run_id.as_str()))
            .cloned();
    }
    snapshots
        .iter()
        .max_by_key(|snapshot| {
            snapshot
                .get("lastUpdatedAt")
                .and_then(Value::as_str)
                .unwrap_or("")
        })
        .cloned()
}

fn findings_payload(
    snapshot: &Value,
    args: &HashMap<String, String>,
) -> Vec<HashMap<String, String>> {
    let kind = args
        .get("kind")
        .map(String::as_str)
        .unwrap_or("verified")
        .to_lowercase();
    let items = if kind == "candidate" || kind == "candidates" {
        snapshot
            .get("candidates")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    } else {
        snapshot
            .get("findings")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
    };
    items
        .into_iter()
        .filter_map(|item| finding_map(&item, kind.starts_with("candidate")))
        .collect()
}

fn bughunter_findings_payload(
    snapshot: &Value,
    args: &HashMap<String, String>,
) -> Vec<HashMap<String, String>> {
    findings_payload(snapshot, args)
        .into_iter()
        .filter(|item| item.get("domain").map(String::as_str) == Some("bug"))
        .collect()
}

fn finding_map(item: &Value, is_candidate: bool) -> Option<HashMap<String, String>> {
    let file_path = item.get("filePath")?.as_str()?.to_string();
    let severity = item.get("severity")?.as_str()?.to_string();
    let category = item.get("category")?.as_str()?.to_string();
    let origin = item.get("origin")?.as_str()?.to_string();
    let message = item.get("message")?.as_str()?.to_string();
    let mut map = HashMap::new();
    map.insert("id".to_string(), item.get("id")?.as_str()?.to_string());
    map.insert("severity".to_string(), severity.clone());
    map.insert("category".to_string(), category.clone());
    map.insert("origin".to_string(), origin.clone());
    map.insert(
        "status".to_string(),
        item.get("status")
            .and_then(Value::as_str)
            .unwrap_or(if is_candidate { "new" } else { "open" })
            .to_string(),
    );
    map.insert(
        "kind".to_string(),
        if is_candidate {
            "candidate"
        } else {
            "verified"
        }
        .to_string(),
    );
    map.insert(
        "domain".to_string(),
        if category == "security" || origin == "securityAuditor" {
            "security".to_string()
        } else {
            "bug".to_string()
        },
    );
    map.insert("file_label".to_string(), state::redacted_label(&file_path));
    map.insert(
        "message_summary".to_string(),
        state::redacted_summary(&severity, &category),
    );
    if let Some(line) = item.get("lineNumber").and_then(Value::as_i64) {
        map.insert("line_number".to_string(), line.to_string());
    }
    if let Some(stale) = item.get("staleStatus").and_then(Value::as_str) {
        map.insert("stale_status".to_string(), stale.to_string());
    }
    if let Some(duplicates) = item.get("possibleDuplicateOf").and_then(Value::as_array) {
        let joined = duplicates
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join(", ");
        if !joined.is_empty() {
            map.insert("possible_duplicate_of".to_string(), joined);
        }
    }
    map.insert("message".to_string(), message);
    Some(map)
}

fn status_payload(snapshot: &Value) -> HashMap<String, String> {
    let mut payload = HashMap::new();
    for (key, value) in [
        ("session_id", "sessionId"),
        ("phase", "phase"),
        ("stage", "stage"),
        ("summary", "statusSummary"),
        ("workspace_path", "workspacePath"),
    ] {
        if let Some(value) = snapshot.get(value).and_then(Value::as_str) {
            payload.insert(key.to_string(), value.to_string());
        }
    }
    payload.insert(
        "findings_total".to_string(),
        snapshot
            .get("findings")
            .and_then(Value::as_array)
            .map(|v| v.len())
            .unwrap_or(0)
            .to_string(),
    );
    payload.insert(
        "candidates_total".to_string(),
        snapshot
            .get("candidates")
            .and_then(Value::as_array)
            .map(|v| v.len())
            .unwrap_or(0)
            .to_string(),
    );
    payload
}

fn outcome_payload(snapshot: &Value) -> HashMap<String, String> {
    let mut payload = HashMap::new();
    let outcome = snapshot.get("outcome").unwrap_or(&Value::Null);
    for (key, field) in [
        ("summary", "summary"),
        ("verified_findings", "verifiedFindings"),
        ("false_positives", "falsePositives"),
        ("patches_ready", "patchesReady"),
        ("patches_applied", "patchesApplied"),
        ("prs_opened", "prsOpened"),
        ("merged_patches", "mergedPatches"),
        ("conflicts_detected", "conflictsDetected"),
    ] {
        if let Some(text) = outcome.get(field).and_then(|value| {
            value
                .as_str()
                .map(ToString::to_string)
                .or_else(|| value.as_i64().map(|v| v.to_string()))
                .or_else(|| {
                    value
                        .as_bool()
                        .map(|v| if v { "true".into() } else { "false".into() })
                })
        }) {
            payload.insert(key.to_string(), text);
        }
    }
    payload
}

fn security_gate_payload(snapshot: &Value) -> HashMap<String, String> {
    let mut ready = false;
    if let Some(verified) = snapshot
        .get("verifiedFindings")
        .and_then(|value| value.get("canonicalSnapshot"))
        .and_then(|value| value.get("findings"))
        .and_then(Value::as_object)
    {
        ready = verified.values().any(|finding| {
            finding.get("domain").and_then(Value::as_str) == Some("bug")
                && matches!(
                    finding.get("status").and_then(Value::as_str),
                    Some("verified" | "fixedVerified" | "patchApplied" | "patchPrepared")
                )
        });
    }
    let summary = if ready {
        "security_gate=ready, verified bug baseline available"
    } else {
        "security_gate=blocked, no verified bughunter baseline is available"
    };
    HashMap::from([
        (
            "ready".to_string(),
            if ready {
                "true".to_string()
            } else {
                "false".to_string()
            },
        ),
        ("summary".to_string(), summary.to_string()),
    ])
}

fn cluster_payload(snapshot: &Value) -> Option<HashMap<String, String>> {
    let findings = snapshot
        .get("verifiedFindings")?
        .get("canonicalSnapshot")?
        .get("findings")?
        .as_object()?;
    let bug_titles = findings
        .values()
        .filter(|finding| finding.get("domain").and_then(Value::as_str) == Some("bug"));
    let mut grouped: HashMap<String, Vec<&Value>> = HashMap::new();
    for finding in bug_titles {
        let title = finding.get("title").and_then(Value::as_str).unwrap_or("");
        let key = title.split('.').next().unwrap_or(title).trim().to_string();
        grouped.entry(key).or_default().push(finding);
    }
    let (title, members) = grouped.into_iter().max_by_key(|(_, items)| items.len())?;
    let files = members
        .iter()
        .filter_map(|finding| finding.get("filePath").and_then(Value::as_str))
        .collect::<Vec<_>>();
    let avg = members
        .iter()
        .filter_map(|finding| finding.get("confidence").and_then(Value::as_f64))
        .sum::<f64>()
        / (members.len().max(1) as f64);
    Some(HashMap::from([
        ("cluster_title".to_string(), title),
        ("cluster_size".to_string(), members.len().to_string()),
        ("files".to_string(), files.join(", ")),
        ("avg_confidence".to_string(), format!("{avg:.2}")),
        (
            "primary_risk".to_string(),
            members
                .first()
                .and_then(|finding| finding.get("category").and_then(Value::as_str))
                .unwrap_or("unknown")
                .to_string(),
        ),
    ]))
}

fn bughunter_status_payload_from_review(_snapshots: &[Value]) -> Option<HashMap<String, String>> {
    None
}

fn preview_patch(args: &HashMap<String, String>) -> CallToolResult {
    let session_id = args
        .get("session_id")
        .or_else(|| args.get("sessionId"))
        .cloned()
        .unwrap_or_default();
    let finding_id = args.get("finding_id").cloned().unwrap_or_default();
    let Some(snapshot) = state::read_review_snapshot(&session_id) else {
        return CallToolResult::error("Error: unable to load the requested review session");
    };
    let patch = snapshot
        .get("patches")
        .and_then(Value::as_array)
        .and_then(|items| {
            items.iter().find(|item| {
                item.get("findingId").and_then(Value::as_str) == Some(finding_id.as_str())
            })
        });
    let Some(patch) = patch else {
        return CallToolResult::text("No patch artifact available for the requested finding.");
    };
    let lines = [
        format!("finding_id: {finding_id}"),
        format!(
            "patch_id: {}",
            patch.get("id").and_then(Value::as_str).unwrap_or("n/a")
        ),
        format!(
            "status: {}",
            patch.get("status").and_then(Value::as_str).unwrap_or("n/a")
        ),
        format!(
            "verify_status: {}",
            patch
                .get("verifyStatus")
                .and_then(Value::as_str)
                .unwrap_or("n/a")
        ),
        format!(
            "validation_status: {}",
            patch
                .get("validationStatus")
                .and_then(Value::as_str)
                .unwrap_or("n/a")
        ),
        "diff_preview:".to_string(),
        patch
            .get("diffPreview")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
    ];
    CallToolResult::text(lines.join("\n"))
}

fn diff_summary(args: &HashMap<String, String>) -> CallToolResult {
    let origin_filter = args
        .get("origin")
        .cloned()
        .unwrap_or_default()
        .trim()
        .to_string();
    if !origin_filter.is_empty() {
        let valid_origins = ["reviewer", "bugHunter", "securityAuditor", "audit_tool"];
        if !valid_origins.contains(&origin_filter.as_str()) {
            return CallToolResult::error(format!(
                "Error: invalid origin '{}'. Use: reviewer, bugHunter, securityAuditor, audit_tool",
                origin_filter
            ));
        }
    }

    let category_filter = args
        .get("category")
        .cloned()
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    if !category_filter.is_empty() {
        let valid_categories = [
            "correctness",
            "regression",
            "concurrency",
            "security",
            "tests",
            "maintainability",
            "performance",
            "other",
        ];
        if !valid_categories.contains(&category_filter.as_str()) {
            return CallToolResult::error(format!(
                "Error: invalid category '{}'. Use: correctness, regression, concurrency, security, tests, maintainability, performance, other",
                category_filter
            ));
        }
    }

    let snapshots = state::read_review_snapshots();
    let Some(snapshot) = resolve_active_review_snapshot(&snapshots, args) else {
        return CallToolResult::error("Error: unable to load the requested review session");
    };

    let workspace_path = snapshot
        .get("workspacePath")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| {
            std::env::current_dir()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned()
        });

    let filtered_files = filtered_diff_files(&snapshot, &origin_filter, &category_filter);
    let file_filter = args
        .get("file")
        .map(String::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);

    match render_summary(ReviewDiffSummaryRequest {
        schema_version: 1,
        snapshot,
        workspace_path,
        file_filter,
        filtered_files,
    }) {
        Ok(summary) => CallToolResult::text(summary),
        Err(message) => CallToolResult::error(format!("Error: {message}")),
    }
}

fn filtered_diff_files(
    snapshot: &Value,
    origin_filter: &str,
    category_filter: &str,
) -> Option<Vec<String>> {
    if origin_filter.is_empty() && category_filter.is_empty() {
        return None;
    }

    let mut files = snapshot
        .get("findings")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|finding| {
            let origin_matches = origin_filter.is_empty()
                || finding.get("origin").and_then(Value::as_str) == Some(origin_filter);
            let category_matches = category_filter.is_empty()
                || finding
                    .get("category")
                    .and_then(Value::as_str)
                    .map(|value| value.eq_ignore_ascii_case(category_filter))
                    .unwrap_or(false);
            origin_matches && category_matches
        })
        .filter_map(|finding| finding.get("filePath").and_then(Value::as_str))
        .map(ToString::to_string)
        .collect::<Vec<_>>();

    files.sort();
    files.dedup();
    Some(files)
}

fn should_enqueue_review_action(name: &str) -> bool {
    matches!(
        name,
        "coderide_review_start"
            | "coderide_review_apply_fix"
            | "coderide_review_dismiss"
            | "coderide_review_comment"
            | "coderide_review_configure"
            | "coderide_review_verify_finding"
            | "coderide_review_prepare_patch"
            | "coderide_review_apply_patch"
            | "coderide_review_verify_patch"
            | "coderide_review_revalidate_finding"
            | "coderide_review_rollback_patch"
            | "coderide_review_close_finding"
            | "coderide_review_open_pr"
            | "coderide_review_merge_pr"
            | "coderide_review_resolve_conflicts"
    )
}

fn should_enqueue_bughunter_action(name: &str) -> bool {
    matches!(
        name,
        "coderide_bughunter_cancel_run"
            | "coderide_bughunter_autofix_preview"
            | "coderide_bughunter_autofix_apply"
            | "coderide_bughunter_autofix_commit"
            | "coderide_bughunter_install_hook"
            | "coderide_bughunter_uninstall_hook"
    )
}

fn security_action(name: &str) -> &str {
    match name {
        "coderide_security_start" => "start",
        _ => name.trim_start_matches("coderide_security_"),
    }
}

fn review_action(name: &str) -> &str {
    match name {
        "coderide_review_start" => "start",
        "coderide_review_apply_fix" => "apply_fix",
        "coderide_review_open_pr" => "open_pr",
        "coderide_review_merge_pr" => "merge_pr",
        "coderide_review_resolve_conflicts" => "resolve_conflicts",
        _ => name.trim_start_matches("coderide_review_"),
    }
}

fn security_payload(name: &str, args: &HashMap<String, String>) -> HashMap<String, String> {
    if name != "coderide_security_start" {
        return args.clone();
    }
    let mut payload = args.clone();
    payload.insert("analysis_only".to_string(), "true".to_string());
    payload.insert(
        "auto_prepare_verified_patches".to_string(),
        "true".to_string(),
    );
    payload.insert(
        "auto_prepare_origin_filter".to_string(),
        "securityAuditor".to_string(),
    );
    payload.insert(
        "review_prompt_override".to_string(),
        "Security-focused review".to_string(),
    );
    payload
}

static UUID_COUNTER: AtomicU64 = AtomicU64::new(0);

fn uuid_like() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;
    let seq = UUID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{:016x}-{:04x}", nanos, seq)
}

fn as_string_args(arguments: &BTreeMap<String, Value>) -> HashMap<String, String> {
    arguments
        .iter()
        .map(|(key, value)| {
            let text = match value {
                Value::String(text) => text.clone(),
                Value::Bool(flag) => flag.to_string(),
                Value::Number(number) => number.to_string(),
                Value::Null => String::new(),
                other => other.to_string(),
            };
            (key.clone(), text)
        })
        .collect()
}
