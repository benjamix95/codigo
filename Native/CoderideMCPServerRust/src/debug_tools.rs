use app_core_protocol::mcp::{CallToolResult, ToolContent};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::collections::hash_map::DefaultHasher;
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static DEBUG_ID_COUNTER: AtomicU64 = AtomicU64::new(0);
/// Serializza lettura/scrittura del JSON debug per workspace (evita lost update tra tool concorrenti).
static DEBUG_STORE_IO: Mutex<()> = Mutex::new(());

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugStore {
    phase: Option<String>,
    session_active: bool,
    session_id: Option<String>,
    workspace_path: Option<String>,
    resolved_summary: Option<String>,
    logs: Vec<DebugLogEntry>,
    hypotheses: Vec<DebugHypothesis>,
    snapshots: Vec<DebugSnapshot>,
    failing_test_filters: Vec<String>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugLogEntry {
    id: String,
    timestamp: String,
    severity: String,
    source: String,
    message: String,
    detail: Option<String>,
    category: Option<String>,
    session_id: Option<String>,
    run_id: Option<String>,
    hypothesis_id: Option<String>,
    data: BTreeMap<String, String>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugHypothesis {
    id: String,
    title: String,
    status: String,
    description: String,
    confidence: i64,
    root_cause_type: String,
    related_files: Vec<String>,
    related_tests: Vec<String>,
    evidence: Vec<String>,
    created_at: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugSnapshot {
    label: String,
    timestamp: String,
    log_count: usize,
    error_count: usize,
    warning_count: usize,
    hypothesis_count: usize,
    confirmed_count: usize,
    rejected_count: usize,
}

#[derive(Clone)]
struct DebugTestExecution {
    scheme: String,
    only_testing: Vec<String>,
}

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_debug_log" => Some(debug_log(workspace, arguments)),
        "coderide_debug_query" => Some(debug_query(workspace, arguments)),
        "coderide_debug_set_phase" => Some(debug_set_phase(workspace, arguments)),
        "coderide_debug_request_user" => Some(debug_request_user(arguments)),
        "coderide_debug_resolve" => Some(debug_resolve(workspace, arguments)),
        "coderide_debug_session" => Some(debug_session(workspace, arguments)),
        "coderide_debug_hypothesize" => Some(debug_hypothesize(workspace, arguments)),
        "coderide_debug_timeline" => Some(debug_timeline(workspace, arguments)),
        "coderide_debug_snapshot" => Some(debug_snapshot(workspace, arguments)),
        "coderide_debug_trace_analyze" => Some(debug_trace_analyze(arguments)),
        "coderide_debug_context" => Some(debug_context(workspace)),
        "coderide_debug_test_check" => Some(debug_test_check(workspace, arguments)),
        "coderide_debug_mark" => Some(debug_mark(workspace, arguments)),
        "coderide_debug_clean" => Some(debug_clean(workspace, arguments)),
        "coderide_debug_instrument" => Some(debug_instrument(workspace, arguments)),
        _ => None,
    }
}

fn debug_set_phase(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let phase = string_arg(arguments, "phase").to_lowercase();
    let valid = [
        "describing",
        "reproducing",
        "fixing",
        "instrumenting",
        "verifying",
        "resolved",
    ];
    if phase.is_empty() {
        return error_result("Error: 'phase' parameter is required", json!({ "error_code": "validation" }));
    }
    if !valid.contains(&phase.as_str()) {
        return error_result(
            format!("Error: invalid phase '{phase}'. Use: {}", valid.join(", ")),
            json!({ "error_code": "validation" }),
        );
    }
    let mut store = read_store(workspace);
    store.phase = Some(phase.clone());
    push_log(
        &mut store,
        "info",
        "debug_set_phase",
        format!("Phase -> {phase}"),
        None,
        Some("system".to_string()),
        None,
    );
    persist_store(workspace, &store);
    text_with_structured(
        format!("OK — debug phase set to {phase}"),
        json!({ "tool": "debug_set_phase", "phase": phase }),
    )
}

fn debug_request_user(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let kind = string_arg(arguments, "kind").to_lowercase();
    let prompt = string_arg(arguments, "prompt");
    if kind.is_empty() || prompt.is_empty() {
        return error_result("Error: 'kind' and 'prompt' are required", json!({ "error_code": "validation" }));
    }
    if !["question", "reproduce", "fix_confirmation"].contains(&kind.as_str()) {
        return error_result(
            "Error: invalid kind. Use: question, reproduce, or fix_confirmation",
            json!({ "error_code": "validation" }),
        );
    }
    text_with_structured(
        format!("OK — debug user request queued ({kind})"),
        json!({ "tool": "debug_request_user", "kind": kind, "prompt": prompt }),
    )
}

fn debug_resolve(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let summary = string_arg(arguments, "summary");
    if summary.is_empty() {
        return error_result("Error: 'summary' is required", json!({ "error_code": "validation" }));
    }
    let mut store = read_store(workspace);
    store.resolved_summary = Some(summary.clone());
    store.phase = Some("resolved".to_string());
    push_log(
        &mut store,
        "info",
        "debug_resolve",
        "Debug session resolved".to_string(),
        Some(summary.clone()),
        Some("system".to_string()),
        None,
    );
    persist_store(workspace, &store);
    text_with_structured(
        "OK — debug session resolved".to_string(),
        json!({ "tool": "debug_resolve", "summary": summary }),
    )
}

fn debug_log(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let severity = non_empty(string_arg(arguments, "severity")).unwrap_or_else(|| "info".to_string());
    let source = non_empty(string_arg(arguments, "source")).unwrap_or_else(|| "agent".to_string());
    let message = string_arg(arguments, "message");
    if message.is_empty() {
        return error_result("Error: 'message' is required", json!({ "error_code": "validation" }));
    }
    let detail = non_empty(string_arg(arguments, "detail"));
    let category = non_empty(string_arg(arguments, "category"));
    let run_id = non_empty(string_arg(arguments, "run_id"));
    let hypothesis_id = non_empty(string_arg(arguments, "hypothesis_id"));
    let data = parse_json_map(string_arg(arguments, "data"));

    let mut store = read_store(workspace);
    push_log(&mut store, &severity, &source, message.clone(), detail, category, hypothesis_id.clone());
    if let Some(last) = store.logs.last_mut() {
        last.run_id = run_id.clone();
        last.data = data.clone();
    }
    persist_store(workspace, &store);

    text_with_structured(
        "OK — debug log entry recorded".to_string(),
        json!({
            "tool": "debug_log",
            "severity": severity,
            "source": source,
            "message": message,
            "category": store.logs.last().and_then(|entry| entry.category.clone()).unwrap_or_default(),
            "run_id": run_id.unwrap_or_default(),
            "hypothesis_id": hypothesis_id.unwrap_or_default(),
            "data": data
        }),
    )
}

fn debug_query(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let store = read_store(workspace);
    let search = string_arg(arguments, "search").to_lowercase();
    let severity = string_arg(arguments, "severity").to_lowercase();
    let hypothesis_id = string_arg(arguments, "hypothesis_id").to_lowercase();

    let filtered = store.logs.iter().filter(|entry| {
        (severity.is_empty() || entry.severity.to_lowercase() == severity)
            && (search.is_empty()
                || entry.message.to_lowercase().contains(&search)
                || entry
                    .detail
                    .as_deref()
                    .unwrap_or_default()
                    .to_lowercase()
                    .contains(&search))
            && (hypothesis_id.is_empty()
                || entry
                    .hypothesis_id
                    .as_deref()
                    .unwrap_or_default()
                    .to_lowercase()
                    .starts_with(&hypothesis_id))
    });

    let lines = filtered
        .map(|entry| format!("[{}] {} — {}", entry.severity, entry.source, entry.message))
        .collect::<Vec<_>>();
    if lines.is_empty() {
        text_with_structured("No debug logs found.".to_string(), json!({ "tool": "debug_query", "count": 0 }))
    } else {
        text_with_structured(lines.join("\n"), json!({ "tool": "debug_query", "count": lines.len() }))
    }
}

fn debug_session(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store(workspace);
    match string_arg(arguments, "action").to_lowercase().as_str() {
        "start" => {
            let session_id = generate_id("dbg");
            store.session_active = true;
            store.session_id = Some(session_id.clone());
            store.workspace_path = Some(workspace.display().to_string());
            store.resolved_summary = None;
            store.failing_test_filters.clear();
            push_log(
                &mut store,
                "info",
                "debug_session",
                "Debug session started".to_string(),
                None,
                Some("system".to_string()),
                None,
            );
            persist_store(workspace, &store);
            text_with_structured(
                "OK — debug session started".to_string(),
                json!({
                    "tool": "debug_session",
                    "action": "start",
                    "session_id": session_id,
                    "workspace_path": workspace.display().to_string()
                }),
            )
        }
        "end" | "stop" => {
            let resolved_summary = store.resolved_summary.clone();
            push_log(
                &mut store,
                "info",
                "debug_session",
                "Debug session ended".to_string(),
                resolved_summary.clone(),
                Some("system".to_string()),
                None,
            );
            store.session_active = false;
            let output = store
                .resolved_summary
                .clone()
                .unwrap_or_else(|| "Debug session ended".to_string());
            persist_store(workspace, &store);
            text_with_structured(
                "OK — debug session ended".to_string(),
                json!({
                    "tool": "debug_session",
                    "action": "stop",
                    "session_id": store.session_id.clone().unwrap_or_default(),
                    "workspace_path": store.workspace_path.clone().unwrap_or_default(),
                    "output": output
                }),
            )
        }
        "clear" => {
            persist_store(workspace, &DebugStore::default());
            text_with_structured(
                "OK — debug session cleared".to_string(),
                json!({ "tool": "debug_session", "action": "clear" }),
            )
        }
        "export" => {
            let report = export_report(&store);
            text_with_structured(
                "OK — debug session exported".to_string(),
                json!({
                    "tool": "debug_session",
                    "action": "export",
                    "session_id": store.session_id.clone().unwrap_or_default(),
                    "workspace_path": store.workspace_path.clone().unwrap_or_default(),
                    "output": report
                }),
            )
        }
        "stats" => {
            let errors = store.logs.iter().filter(|entry| entry.severity == "error").count();
            let warnings = store.logs.iter().filter(|entry| entry.severity == "warning").count();
            let stats = format!(
                "session_active: {}\nlogs: {}\nerrors: {}\nwarnings: {}\nhypotheses: {}",
                store.session_active,
                store.logs.len(),
                errors,
                warnings,
                store.hypotheses.len()
            );
            text_with_structured(
                stats.clone(),
                json!({
                    "tool": "debug_session",
                    "action": "stats",
                    "session_id": store.session_id.clone().unwrap_or_default(),
                    "workspace_path": store.workspace_path.clone().unwrap_or_default(),
                    "output": stats
                }),
            )
        }
        _ => error_result(
            "Error: unsupported debug_session action",
            json!({ "error_code": "validation" }),
        ),
    }
}

fn debug_hypothesize(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store(workspace);
    let action = string_arg(arguments, "action").to_lowercase();
    let confidence_raw = string_arg(arguments, "confidence");
    let confidence_parsed = if confidence_raw.is_empty() {
        None
    } else {
        Some(confidence_raw.parse::<i64>().unwrap_or(50).clamp(0, 100))
    };
    let root_cause_type = string_arg(arguments, "root_cause_type");
    let related_files = parse_csv(string_arg(arguments, "related_files"));
    let related_tests = parse_csv(string_arg(arguments, "related_tests"));
    let evidence = non_empty(string_arg(arguments, "evidence"));

    match action.as_str() {
        "propose" => {
            let title = string_arg(arguments, "title");
            if title.is_empty() {
                return error_result("Error: 'title' is required", json!({ "error_code": "validation" }));
            }
            let id = generate_id("hyp");
            let status = non_empty(string_arg(arguments, "status")).unwrap_or_else(|| "proposed".to_string());
            let mut hypothesis = DebugHypothesis {
                id: id.clone(),
                title: title.clone(),
                status: status.clone(),
                description: string_arg(arguments, "description"),
                confidence: confidence_parsed.unwrap_or(50),
                root_cause_type,
                related_files,
                related_tests,
                evidence: vec![],
                created_at: now_string(),
            };
            if let Some(item) = evidence.clone() {
                hypothesis.evidence.push(item);
            }
            store.hypotheses.push(hypothesis.clone());
            push_log(
                &mut store,
                "info",
                "debug_hypothesize",
                format!("Hypothesis {} proposed: {}", short_id(&id), title),
                evidence,
                Some("debug".to_string()),
                Some(id.clone()),
            );
            persist_store(workspace, &store);
            text_with_structured(
                "OK — debug hypothesis proposed".to_string(),
                json!({
                    "tool": "debug_hypothesize",
                    "action": "propose",
                    "hypothesis_id": id,
                    "hypothesis_title": title,
                    "description": hypothesis.description,
                    "hypothesis_status": status,
                    "confidence": hypothesis.confidence,
                    "root_cause_type": hypothesis.root_cause_type,
                    "related_files": hypothesis.related_files.join(","),
                    "related_tests": hypothesis.related_tests.join(","),
                    "evidence": hypothesis.evidence.join("|||")
                }),
            )
        }
        "update" => {
            let hypothesis_id = string_arg(arguments, "hypothesis_id");
            let resolved = resolve_hypothesis_id(&store, &hypothesis_id);
            let Some(resolved_id) = resolved else {
                return error_result("Error: hypothesis not found", json!({ "error_code": "validation" }));
            };
            let Some(existing) = store.hypotheses.iter_mut().find(|item| item.id == resolved_id) else {
                return error_result("Error: hypothesis not found", json!({ "error_code": "validation" }));
            };
            let next_status = non_empty(string_arg(arguments, "status")).unwrap_or_else(|| existing.status.clone());
            existing.status = next_status.clone();
            if let Some(c) = confidence_parsed {
                existing.confidence = c;
            }
            if !string_arg(arguments, "description").is_empty() {
                existing.description = string_arg(arguments, "description");
            }
            if !string_arg(arguments, "root_cause_type").is_empty() {
                existing.root_cause_type = string_arg(arguments, "root_cause_type");
            }
            if !parse_csv(string_arg(arguments, "related_files")).is_empty() {
                existing.related_files = parse_csv(string_arg(arguments, "related_files"));
            }
            if !parse_csv(string_arg(arguments, "related_tests")).is_empty() {
                existing.related_tests = parse_csv(string_arg(arguments, "related_tests"));
            }
            if let Some(item) = evidence.clone() {
                existing.evidence.push(item);
            }
            let snapshot = existing.clone();
            push_log(
                &mut store,
                "info",
                "debug_hypothesize",
                format!("Hypothesis {} updated to {}", short_id(&resolved_id), next_status),
                evidence,
                Some("debug".to_string()),
                Some(resolved_id.clone()),
            );
            persist_store(workspace, &store);
            text_with_structured(
                "OK — debug hypothesis updated".to_string(),
                json!({
                    "tool": "debug_hypothesize",
                    "action": "update",
                    "hypothesis_id": resolved_id,
                    "hypothesis_title": snapshot.title,
                    "description": snapshot.description,
                    "hypothesis_status": snapshot.status,
                    "confidence": snapshot.confidence,
                    "root_cause_type": snapshot.root_cause_type,
                    "related_files": snapshot.related_files.join(","),
                    "related_tests": snapshot.related_tests.join(","),
                    "evidence": snapshot.evidence.join("|||")
                }),
            )
        }
        _ => error_result(
            "Error: unsupported debug_hypothesize action",
            json!({ "error_code": "validation" }),
        ),
    }
}

fn debug_timeline(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let store = read_store(workspace);
    let filter = string_arg(arguments, "filter").to_lowercase();
    let show_all = filter.is_empty() || filter == "all";
    let mut lines = Vec::new();
    if show_all || filter.contains("phases") {
        if let Some(phase) = store.phase.as_deref() {
            lines.push(format!("phase: {phase}"));
        }
    }
    if show_all || filter.contains("hypotheses") {
        for hypothesis in &store.hypotheses {
            lines.push(format!(
                "hypothesis {} [{}] {}",
                short_id(&hypothesis.id),
                hypothesis.status,
                hypothesis.title
            ));
        }
    }
    if show_all || filter.contains("logs") {
        for entry in &store.logs {
            lines.push(format!(
                "{} [{}] {} — {}",
                entry.timestamp, entry.severity, entry.source, entry.message
            ));
        }
    }
    let output = if lines.is_empty() {
        "No debug timeline available.".to_string()
    } else {
        lines.join("\n")
    };
    text_with_structured(
        output.clone(),
        json!({ "tool": "debug_timeline", "output": output, "format": string_arg(arguments, "format") }),
    )
}

fn debug_snapshot(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store(workspace);
    let action = string_arg(arguments, "action").to_lowercase();
    match action.as_str() {
        "capture" => {
            let label = non_empty(string_arg(arguments, "label"))
                .unwrap_or_else(|| format!("snapshot-{}", store.snapshots.len() + 1));
            let snapshot = build_snapshot(&store, &label);
            store.snapshots.retain(|item| item.label != label);
            store.snapshots.push(snapshot.clone());
            persist_store(workspace, &store);
            text_with_structured(
                format!("Snapshot '{}' captured", label),
                json!({
                    "tool": "debug_snapshot",
                    "action": "capture",
                    "label": snapshot.label,
                    "detail": format!("Snapshot '{}' captured", snapshot.label),
                    "output": snapshot_summary(&snapshot)
                }),
            )
        }
        "compare" => {
            let label = string_arg(arguments, "label");
            let compare_with = string_arg(arguments, "compare_with");
            let current = build_snapshot(&store, &label);
            let Some(previous) = store.snapshots.iter().find(|item| item.label == compare_with) else {
                return error_result("Error: snapshot not found", json!({ "error_code": "validation" }));
            };
            let output = format!(
                "Snapshot compare {} -> {}\nlogs: {} -> {}\nerrors: {} -> {}\nwarnings: {} -> {}\nhypotheses: {} -> {}",
                previous.label,
                label,
                previous.log_count,
                current.log_count,
                previous.error_count,
                current.error_count,
                previous.warning_count,
                current.warning_count,
                previous.hypothesis_count,
                current.hypothesis_count
            );
            text_with_structured(
                output.clone(),
                json!({
                    "tool": "debug_snapshot",
                    "action": "compare",
                    "label": label,
                    "compare_with": compare_with,
                    "detail": format!("Compared '{}' with '{}'", compare_with, label),
                    "output": output
                }),
            )
        }
        "list" => {
            let output = if store.snapshots.is_empty() {
                "No snapshots have been captured yet.".to_string()
            } else {
                store.snapshots
                    .iter()
                    .map(|item| format!("{} ({})", item.label, item.timestamp))
                    .collect::<Vec<_>>()
                    .join("\n")
            };
            text_with_structured(
                output.clone(),
                json!({ "tool": "debug_snapshot", "action": "list", "output": output }),
            )
        }
        _ => error_result("Error: unsupported debug_snapshot action", json!({ "error_code": "validation" })),
    }
}

fn debug_trace_analyze(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let error_text = string_arg(arguments, "error_text");
    if error_text.is_empty() {
        return error_result("Error: 'error_text' is required", json!({ "error_code": "validation" }));
    }
    let error_type = non_empty(string_arg(arguments, "error_type")).unwrap_or_else(|| detect_error_type(&error_text));
    let output = format!(
        "error_type: {}\nsummary: inspect the first failing frame, validate the nearest changed callsite, and confirm with targeted tests.",
        error_type
    );
    text_with_structured(
        output.clone(),
        json!({
            "tool": "debug_trace_analyze",
            "error_type": error_type,
            "detail": "Trace analyzed",
            "output": output
        }),
    )
}

fn debug_context(workspace: &Path) -> CallToolResult {
    let mut sections = vec![format!("workspace: {}", workspace.display())];
    if let Some(status) = run_command(workspace, "/usr/bin/git", &["status", "--short", "--branch"]) {
        if !status.trim().is_empty() {
            sections.push(format!("git:\n{}", status.trim()));
        }
    }
    if let Some(version) = run_command(workspace, "/usr/bin/xcodebuild", &["-version"]) {
        if !version.trim().is_empty() {
            sections.push(format!("xcodebuild:\n{}", version.trim()));
        }
    }
    if let Ok(entries) = fs::read_dir(workspace) {
        let listed = entries
            .flatten()
            .take(20)
            .map(|entry| entry.file_name().to_string_lossy().to_string())
            .collect::<Vec<_>>();
        if !listed.is_empty() {
            sections.push(format!("files:\n{}", listed.join("\n")));
        }
    }
    let output = sections.join("\n\n");
    text_with_structured(
        output.clone(),
        json!({ "tool": "debug_context", "detail": "Debug context gathered", "output": output }),
    )
}

fn debug_test_check(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let scope = non_empty(string_arg(arguments, "scope")).unwrap_or_else(|| "related".to_string());
    let filter = string_arg(arguments, "filter");
    let path = string_arg(arguments, "path");
    let mut store = read_store(workspace);

    let xcodebuild = resolved_xcodebuild_path();
    let Some(xcodebuild) = xcodebuild else {
        return error_result("Unable to locate xcodebuild", json!({ "error_code": "validation" }));
    };

    let executions = if scope == "failing" {
        if store.failing_test_filters.is_empty() {
            return text_with_structured(
                "No previously failing Xcode tests recorded in this runtime session.".to_string(),
                json!({
                    "tool": "debug_test_check",
                    "scope": scope,
                    "overall_status": "skipped",
                    "passed": 0,
                    "failed": 0
                }),
            );
        }
        grouped_executions_for_filters(&store.failing_test_filters)
    } else if scope == "integration" {
        vec![DebugTestExecution {
            scheme: "Solo Code-IntegrationTests".to_string(),
            only_testing: if filter.is_empty() { vec!["SoloCodeIntegrationTests".to_string()] } else { vec![filter.clone()] },
        }]
    } else if !filter.is_empty() {
        grouped_executions_for_filters(&parse_csv(filter.clone()))
    } else {
        executions_for_files(&path)
    };

    if executions.is_empty() {
        return error_result(
            "No Xcode test scheme could be resolved for debug_test_check",
            json!({ "error_code": "validation" }),
        );
    }

    let mut outputs = Vec::new();
    let mut failing = Vec::new();
    let mut passed = 0;
    let mut failed = 0;
    let mut exit_code = 0;

    for execution in &executions {
        let mut cmd = Command::new(&xcodebuild);
        cmd.current_dir(workspace)
            .arg("test")
            .arg("-workspace")
            .arg("Solo Code.xcworkspace")
            .arg("-scheme")
            .arg(&execution.scheme)
            .arg("-destination")
            .arg("platform=macOS")
            .arg("CODE_SIGNING_ALLOWED=NO");
        for identifier in &execution.only_testing {
            cmd.arg(format!("-only-testing:{identifier}"));
        }
        let output = match cmd.output() {
            Ok(value) => value,
            Err(error) => {
                return error_result(
                    format!("Failed to run xcodebuild: {error}"),
                    json!({ "error_code": "validation" }),
                )
            }
        };
        exit_code = output.status.code().unwrap_or(1);
        let combined = format!(
            "{}{}{}",
            String::from_utf8_lossy(&output.stdout),
            if output.stderr.is_empty() { "" } else { "\n" },
            String::from_utf8_lossy(&output.stderr)
        );
        let parsed = parse_xcode_test_output(&combined);
        passed += parsed.0;
        failed += parsed.1;
        failing.extend(parsed.2);
        outputs.push(format!("### {}\n{}", execution.scheme, combined.trim()));
        if exit_code != 0 {
            break;
        }
    }

    store.failing_test_filters = dedupe(failing.clone());
    if exit_code == 0 {
        store.failing_test_filters.clear();
    }
    persist_store(workspace, &store);

    let output = format!(
        "Xcode tests {}: {} passed, {} failed\nschemes: {}\n{}",
        if exit_code == 0 { "PASSED" } else { "FAILED" },
        passed,
        failed,
        executions.iter().map(|item| item.scheme.clone()).collect::<Vec<_>>().join(", "),
        outputs.join("\n\n")
    );
    text_with_structured(
        if exit_code == 0 {
            "OK — debug test check passed".to_string()
        } else {
            "OK — debug test check failed".to_string()
        },
        json!({
            "tool": "debug_test_check",
            "scope": scope,
            "detail": format!("{}: {} passed, {} failed [{}]", if exit_code == 0 { "PASSED" } else { "FAILED" }, passed, failed, scope),
            "output": output,
            "passed": passed,
            "failed": failed,
            "overall_status": if exit_code == 0 { "passed" } else { "failed" },
            "schemes": executions.iter().map(|item| item.scheme.clone()).collect::<Vec<_>>().join(","),
            "filter": filter
        }),
    )
}

fn debug_mark(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = string_arg(arguments, "path");
    let line = string_arg(arguments, "line").parse::<usize>().unwrap_or(0);
    let comment = non_empty(string_arg(arguments, "comment")).unwrap_or_else(|| "DEBUG".to_string());
    let code = string_arg(arguments, "code");
    let marker_type = non_empty(string_arg(arguments, "type"))
        .unwrap_or_else(|| "marker".to_string())
        .to_lowercase();
    let expression = string_arg(arguments, "expression");
    let hypothesis_id = short_id(&string_arg(arguments, "hypothesis_id"));
    if path.is_empty() || line == 0 {
        return error_result("Error: path and line are required", json!({ "error_code": "validation" }));
    }
    let file_path = resolve_path(workspace, &path);
    let mut lines = match read_lines(&file_path) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let tag = hypothesis_tag(&hypothesis_id);
    let marker = if !code.is_empty() {
        format!("{code} // [DEBUG:{marker_type}] {comment}{tag}")
    } else {
        match marker_type.as_str() {
            "log" => {
                let expr = if expression.is_empty() { "\"checkpoint\"" } else { expression.as_str() };
                format!("print(\"[DEBUG] {comment}: \\({expr})\") // [DEBUG:log] {comment}{tag}")
            }
            "assert" => {
                let expr = if expression.is_empty() { "true" } else { expression.as_str() };
                format!("assert({expr}, \"[DEBUG ASSERT] {comment}\") // [DEBUG:assert] {comment}{tag}")
            }
            "timing" => format!(
                "let _debugTimerStart_{line} = CFAbsoluteTimeGetCurrent(); defer {{ print(\"[DEBUG TIMING] {comment}: \\(CFAbsoluteTimeGetCurrent() - _debugTimerStart_{line})s\") }} // [DEBUG:timing] {comment}{tag}"
            ),
            "variable" => {
                let expr = if expression.is_empty() { "self" } else { expression.as_str() };
                format!("print(\"[DEBUG VAR] {comment} {expr} = \\({expr})\") // [DEBUG:variable] {comment}{tag}")
            }
            _ => format!("// [DEBUG:marker] {comment}{tag}"),
        }
    };
    let insert_at = line.min(lines.len());
    lines.insert(insert_at, marker.clone());
    if let Err(error) = write_lines(&file_path, &lines) {
        return error_result(format!("Error: {error}"), json!({ "error_code": "write_failed" }));
    }
    text_with_structured(
        "OK — debug marker inserted".to_string(),
        json!({
            "tool": "debug_mark",
            "path": file_path.display().to_string(),
            "line": line,
            "comment": comment,
            "type": marker_type,
            "hypothesis_id": hypothesis_id,
            "marker_info": format!("{}|{}|{}|{}", file_path.display(), line, comment, marker_type)
        }),
    )
}

fn debug_clean(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let raw_path = string_arg(arguments, "path");
    let dry_run = matches!(string_arg(arguments, "dry_run").as_str(), "true" | "1" | "yes");
    let clean_type = non_empty(string_arg(arguments, "type"))
        .unwrap_or_else(|| "all".to_string())
        .to_lowercase();
    let hypothesis_id = short_id(&string_arg(arguments, "hypothesis_id"));
    let files = if raw_path.is_empty() {
        collect_debug_files(workspace)
    } else {
        vec![resolve_path(workspace, &raw_path)]
    };
    let type_patterns: Vec<&str> = match clean_type.as_str() {
        "markers" => vec!["[DEBUG:marker]"],
        "logs" => vec!["[DEBUG:log]", "[DEBUG:instrument-log]"],
        "asserts" => vec!["[DEBUG:assert]", "[DEBUG:instrument-assert]", "[DEBUG:instrument-conditional]"],
        "timing" => vec!["[DEBUG:timing]", "[DEBUG:instrument-timing]"],
        "variables" => vec!["[DEBUG:variable]", "[DEBUG:instrument-variable]"],
        _ => vec!["[DEBUG:"],
    };

    let mut cleaned = 0usize;
    let mut touched = 0usize;
    let mut preview = Vec::new();

    for file in files {
        let Ok(lines) = read_lines(&file) else { continue };
        let mut kept = Vec::new();
        let mut file_cleaned = 0usize;
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            let matches_debug = type_patterns
                .iter()
                .any(|pattern| lower.contains(&pattern.to_lowercase()));
            let matches_hypothesis = hypothesis_id.is_empty() || lower.contains(&format!("[h:{hypothesis_id}]"));
            if matches_debug && matches_hypothesis {
                cleaned += 1;
                file_cleaned += 1;
                if dry_run {
                    preview.push(format!("{}:{} {}", file.display(), index + 1, line.trim()));
                    kept.push(line.clone());
                }
            } else {
                kept.push(line.clone());
            }
        }
        if file_cleaned > 0 {
            touched += 1;
            if !dry_run {
                if let Err(e) = write_lines(&file, &kept) {
                    eprintln!("[debug_tools] WARNING: failed to write cleaned file {}: {e}", file.display());
                }
            }
        }
    }

    let type_label = if clean_type == "all" {
        "all types".to_string()
    } else {
        clean_type.clone()
    };
    let detail = if dry_run {
        format!("[DRY RUN] {cleaned} {type_label} markers in {touched} files")
    } else {
        format!("[CLEANED] {cleaned} {type_label} markers in {touched} files")
    };
    let mut output = detail.clone();
    if !preview.is_empty() {
        output.push_str("\n");
        output.push_str(&preview.join("\n"));
    }
    text_with_structured(
        if dry_run {
            "OK — debug cleanup preview generated".to_string()
        } else {
            "OK — debug markers cleaned".to_string()
        },
        json!({
            "tool": "debug_clean",
            "detail": detail,
            "output": output,
            "cleaned_markers": cleaned,
            "cleaned_files": touched,
            "type": clean_type,
            "dry_run": dry_run,
            "status": if dry_run { "preview" } else { "completed" }
        }),
    )
}

fn debug_instrument(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = string_arg(arguments, "path");
    let line = string_arg(arguments, "line").parse::<usize>().unwrap_or(0);
    let instrument_type = non_empty(string_arg(arguments, "type")).unwrap_or_else(|| "log".to_string());
    let expression = non_empty(string_arg(arguments, "expression")).unwrap_or_else(|| "self".to_string());
    let label = string_arg(arguments, "label");
    let hypothesis_id = short_id(&string_arg(arguments, "hypothesis_id"));
    if path.is_empty() || line == 0 {
        return error_result("Error: path and line are required", json!({ "error_code": "validation" }));
    }

    let tag = hypothesis_tag(&hypothesis_id);
    let label_tag = if label.is_empty() {
        String::new()
    } else {
        format!(" [{label}]")
    };
    let display_label = if label.is_empty() { expression.clone() } else { label.clone() };
    let generated = match instrument_type.as_str() {
        "assert" => {
            let msg = non_empty(string_arg(arguments, "condition")).unwrap_or_else(|| expression.clone());
            format!(
                "assert({}, \"[INSTRUMENT ASSERT]{}: {}\") // [DEBUG:instrument-assert] {}{}",
                expression, label_tag, msg, display_label, tag
            )
        }
        "timing" => format!(
            "let _instrTimer_{line} = CFAbsoluteTimeGetCurrent(); defer {{ print(\"[INSTRUMENT TIMING]{}: \\(String(format: \\\"%.4f\\\", CFAbsoluteTimeGetCurrent() - _instrTimer_{line}))s for {}\") }} // [DEBUG:instrument-timing] {}{}",
            label_tag, expression, display_label, tag
        ),
        "variable" => format!(
            "print(\"[INSTRUMENT VAR]{} {} = \\({}) [type: \\(type(of: {}))]\") // [DEBUG:instrument-variable] {}{}",
            label_tag, expression, expression, expression, display_label, tag
        ),
        "conditional_break" => {
            let condition = non_empty(string_arg(arguments, "condition")).unwrap_or_else(|| "true".to_string());
            format!(
                "if {} {{ print(\"[INSTRUMENT BREAK]{}: condition met - {} = \\({})\") }} // [DEBUG:instrument-conditional] {}{}",
                condition, label_tag, expression, expression, display_label, tag
            )
        }
        _ => format!(
            "print(\"[INSTRUMENT]{}: \\({})\") // [DEBUG:instrument-log] {}{}",
            label_tag, expression, display_label, tag
        ),
    };

    let file_path = resolve_path(workspace, &path);
    let mut lines = match read_lines(&file_path) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let insert_at = line.min(lines.len());
    lines.insert(insert_at, generated.clone());
    if let Err(error) = write_lines(&file_path, &lines) {
        return error_result(format!("Error: {error}"), json!({ "error_code": "write_failed" }));
    }
    text_with_structured(
        "OK — debug instrumentation inserted".to_string(),
        json!({
            "tool": "debug_instrument",
            "path": file_path.display().to_string(),
            "line": line,
            "type": instrument_type,
            "expression": expression,
            "label": label,
            "hypothesis_id": hypothesis_id
        }),
    )
}

fn push_log(
    store: &mut DebugStore,
    severity: &str,
    source: &str,
    message: String,
    detail: Option<String>,
    category: Option<String>,
    hypothesis_id: Option<String>,
) {
    store.logs.push(DebugLogEntry {
        id: generate_id("log"),
        timestamp: now_string(),
        severity: severity.to_string(),
        source: source.to_string(),
        message,
        detail,
        category,
        session_id: store.session_id.clone(),
        run_id: None,
        hypothesis_id,
        data: BTreeMap::new(),
    });
}

fn build_snapshot(store: &DebugStore, label: &str) -> DebugSnapshot {
    DebugSnapshot {
        label: label.to_string(),
        timestamp: now_string(),
        log_count: store.logs.len(),
        error_count: store.logs.iter().filter(|entry| entry.severity == "error").count(),
        warning_count: store.logs.iter().filter(|entry| entry.severity == "warning").count(),
        hypothesis_count: store.hypotheses.len(),
        confirmed_count: store.hypotheses.iter().filter(|item| item.status == "confirmed").count(),
        rejected_count: store.hypotheses.iter().filter(|item| item.status == "rejected").count(),
    }
}

fn snapshot_summary(snapshot: &DebugSnapshot) -> String {
    format!(
        "Snapshot '{}': {} logs, {} errors, {} warnings, {} hypotheses",
        snapshot.label, snapshot.log_count, snapshot.error_count, snapshot.warning_count, snapshot.hypothesis_count
    )
}

fn export_report(store: &DebugStore) -> String {
    let mut report = String::from("# Debug Session Report\n\n");
    if let Some(summary) = store.resolved_summary.as_deref() {
        report.push_str(&format!("## Resolution\n{}\n\n", summary));
    }
    report.push_str(&format!("## Hypotheses ({})\n", store.hypotheses.len()));
    for hypothesis in &store.hypotheses {
        report.push_str(&format!(
            "- {} [{}] {} ({}%)\n",
            short_id(&hypothesis.id),
            hypothesis.status,
            hypothesis.title,
            hypothesis.confidence
        ));
    }
    report.push_str(&format!("\n## Logs ({})\n", store.logs.len()));
    for entry in store.logs.iter().rev().take(50) {
        report.push_str(&format!("- [{}] {}: {}\n", entry.severity, entry.source, entry.message));
    }
    report
}

fn parse_json_map(raw: String) -> BTreeMap<String, String> {
    if raw.trim().is_empty() {
        return BTreeMap::new();
    }
    serde_json::from_str::<BTreeMap<String, Value>>(&raw)
        .ok()
        .map(|map| {
            map.into_iter()
                .map(|(key, value)| (key, value.as_str().map(|item| item.to_string()).unwrap_or_else(|| value.to_string())))
                .collect()
        })
        .unwrap_or_default()
}

fn parse_csv(raw: String) -> Vec<String> {
    raw.split(',')
        .map(|item| item.trim().to_string())
        .filter(|item| !item.is_empty())
        .collect()
}

fn dedupe(values: Vec<String>) -> Vec<String> {
    let mut ordered = Vec::new();
    for value in values {
        if !ordered.contains(&value) {
            ordered.push(value);
        }
    }
    ordered
}

fn grouped_executions_for_filters(filters: &[String]) -> Vec<DebugTestExecution> {
    let mut grouped: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for filter in filters {
        grouped
            .entry(scheme_for_test_identifier(filter))
            .or_default()
            .push(filter.clone());
    }
    grouped
        .into_iter()
        .map(|(scheme, only_testing)| DebugTestExecution { scheme, only_testing })
        .collect()
}

fn executions_for_files(path: &str) -> Vec<DebugTestExecution> {
    if path.is_empty() {
        return vec![DebugTestExecution {
            scheme: "Solo Code-Debug".to_string(),
            only_testing: vec![],
        }];
    }
    let files = parse_csv(path.to_string());
    let mut executions = Vec::new();
    let has_engine = files.iter().any(|file| file.starts_with("Engine/") || file.starts_with("Tools/"));
    let has_app = files.iter().any(|file| file.starts_with("App/"));
    if has_app || !has_engine {
        executions.push(DebugTestExecution {
            scheme: "Solo Code-Debug".to_string(),
            only_testing: vec!["SoloCodeAppTests".to_string()],
        });
    }
    if has_engine {
        executions.push(DebugTestExecution {
            scheme: "CoderEngineTests-Debug".to_string(),
            only_testing: vec!["CoderEngineTests".to_string()],
        });
    }
    executions
}

fn scheme_for_test_identifier(identifier: &str) -> String {
    if identifier.starts_with("CoderEngineTests/") {
        "CoderEngineTests-Debug".to_string()
    } else if identifier.starts_with("SoloCodeIntegrationTests/") {
        "Solo Code-IntegrationTests".to_string()
    } else {
        "Solo Code-Debug".to_string()
    }
}

fn parse_xcode_test_output(output: &str) -> (usize, usize, Vec<String>) {
    let mut passed = 0usize;
    let mut failed = 0usize;
    let mut failing = Vec::new();
    for raw_line in output.lines() {
        let line = raw_line.trim();
        if line.contains("Test Case") && line.contains(" passed") {
            passed += 1;
        } else if line.contains("Test Case") && line.contains(" failed") {
            failed += 1;
            if let Some(identifier) = parse_xcode_test_identifier(line) {
                failing.push(identifier);
            }
        }
    }
    (passed, failed, failing)
}

fn parse_xcode_test_identifier(line: &str) -> Option<String> {
    let start = line.find("-[")?;
    let remainder = &line[start + 2..];
    let end = remainder.find(']')?;
    let raw = &remainder[..end];
    let mut parts = raw.split_whitespace();
    let suite = parts.next()?;
    let method = parts.next()?;
    let mut suite_parts = suite.split('.');
    let bundle = suite_parts.next()?.to_string();
    let class = suite_parts.collect::<Vec<_>>().join(".");
    Some(format!("{bundle}/{class}/{method}"))
}

fn detect_error_type(error_text: &str) -> String {
    let lower = error_text.to_lowercase();
    if lower.contains("assert") {
        "assertion".to_string()
    } else if lower.contains("crash") || lower.contains("fatal") {
        "crash".to_string()
    } else if lower.contains("test") {
        "test_failure".to_string()
    } else if lower.contains("error:") || lower.contains("warning:") {
        "compile".to_string()
    } else {
        "runtime".to_string()
    }
}

/// Max file size to consider for debug file collection (1 MB).
const MAX_DEBUG_FILE_SIZE: u64 = 1_048_576;
/// Max total files to collect to avoid runaway traversal.
const MAX_DEBUG_FILES: usize = 500;

fn collect_debug_files(workspace: &Path) -> Vec<PathBuf> {
    let mut matches = Vec::new();
    let mut stack = vec![workspace.to_path_buf()];
    while let Some(path) = stack.pop() {
        let Ok(entries) = fs::read_dir(&path) else { continue };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                // Skip hidden dirs and common large dirs
                let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
                if name.starts_with('.') || name == "node_modules" || name == "target" || name == "build" {
                    continue;
                }
                stack.push(path);
                continue;
            }
            // Check file size via metadata instead of reading full content
            if let Ok(meta) = path.metadata() {
                if meta.len() <= MAX_DEBUG_FILE_SIZE {
                    matches.push(path);
                }
            }
            if matches.len() >= MAX_DEBUG_FILES {
                return matches;
            }
        }
    }
    matches
}

fn read_lines(path: &Path) -> Result<Vec<String>, CallToolResult> {
    fs::read_to_string(path)
        .map(|content| content.lines().map(|line| line.to_string()).collect())
        .map_err(|error| error_result(format!("Error: {}", error), json!({ "error_code": "read_failed" })))
}

fn write_lines(path: &Path, lines: &[String]) -> Result<(), String> {
    fs::write(path, lines.join("\n")).map_err(|error| error.to_string())
}

fn resolve_path(workspace: &Path, raw: &str) -> PathBuf {
    let path = PathBuf::from(raw);
    if path.is_absolute() {
        path
    } else {
        workspace.join(path)
    }
}

fn resolve_hypothesis_id(store: &DebugStore, raw: &str) -> Option<String> {
    let normalized = raw.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }
    store
        .hypotheses
        .iter()
        .find(|item| item.id.to_lowercase() == normalized || short_id(&item.id) == normalized)
        .map(|item| item.id.clone())
}

fn workspace_fingerprint(workspace: &Path) -> String {
    let normalized = workspace
        .canonicalize()
        .unwrap_or_else(|_| workspace.to_path_buf());
    let key = normalized.to_string_lossy();
    let mut hasher = DefaultHasher::new();
    key.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

fn debug_store_path(workspace: &Path) -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let fp = workspace_fingerprint(workspace);
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared")
        .join("workspaces")
        .join(fp)
        .join("debug_state.json")
}

fn read_store(workspace: &Path) -> DebugStore {
    let _guard = DEBUG_STORE_IO.lock().unwrap();
    let path = debug_store_path(workspace);
    let Ok(data) = fs::read(&path) else {
        return DebugStore::default();
    };
    serde_json::from_slice(&data).unwrap_or_default()
}

fn write_store(workspace: &Path, store: &DebugStore) -> Result<(), String> {
    let path = debug_store_path(workspace);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(store).map_err(|error| error.to_string())?;
    let tmp_path = path.with_extension("json.tmp");
    fs::write(&tmp_path, &data).map_err(|error| error.to_string())?;
    fs::rename(&tmp_path, &path).map_err(|error| error.to_string())
}

/// Wrapper che logga l'errore se write_store fallisce, senza silenziarlo.
fn persist_store(workspace: &Path, store: &DebugStore) {
    let _guard = DEBUG_STORE_IO.lock().unwrap();
    if let Err(e) = write_store(workspace, store) {
        eprintln!("[debug_tools] persist_store failed: {e}");
    }
}

fn resolved_xcodebuild_path() -> Option<String> {
    let override_path = std::env::var("SOLOCODE_DEBUG_XCODEBUILD_PATH").ok().filter(|value| !value.trim().is_empty());
    if let Some(path) = override_path {
        return Some(path);
    }
    Some("/usr/bin/xcodebuild".to_string())
}

fn run_command(workspace: &Path, executable: &str, args: &[&str]) -> Option<String> {
    Command::new(executable)
        .current_dir(workspace)
        .args(args)
        .output()
        .ok()
        .map(|output| {
            format!(
                "{}{}{}",
                String::from_utf8_lossy(&output.stdout),
                if output.stderr.is_empty() { "" } else { "\n" },
                String::from_utf8_lossy(&output.stderr)
            )
        })
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn non_empty(value: String) -> Option<String> {
    if value.is_empty() { None } else { Some(value) }
}

fn now_string() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn generate_id(prefix: &str) -> String {
    let seq = DEBUG_ID_COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{}-{:04x}", now_string(), seq)
}

fn short_id(value: &str) -> String {
    value.chars().take(8).collect()
}

fn hypothesis_tag(hypothesis_id: &str) -> String {
    if hypothesis_id.is_empty() {
        String::new()
    } else {
        format!(" [H:{hypothesis_id}]")
    }
}

fn text_with_structured(text: String, structured: Value) -> CallToolResult {
    CallToolResult {
        content: vec![ToolContent::Text { text }],
        structured_content: Some(structured),
        is_error: None,
    }
}

fn error_result(text: impl Into<String>, structured: Value) -> CallToolResult {
    CallToolResult {
        content: vec![ToolContent::Text { text: text.into() }],
        structured_content: Some(structured),
        is_error: Some(true),
    }
}
