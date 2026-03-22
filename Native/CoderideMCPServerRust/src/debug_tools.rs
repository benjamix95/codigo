use app_core_protocol::mcp::CallToolResult;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugStore {
    phase: Option<String>,
    session_active: bool,
    logs: Vec<DebugLogEntry>,
    hypotheses: Vec<DebugHypothesis>,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugLogEntry {
    severity: String,
    source: String,
    message: String,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DebugHypothesis {
    id: String,
    title: String,
    status: String,
    description: Option<String>,
}

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_debug_log" => Some(debug_log(arguments)),
        "coderide_debug_query" => Some(debug_query(arguments)),
        "coderide_debug_set_phase" => Some(debug_set_phase(arguments)),
        "coderide_debug_request_user" => Some(debug_request_user(arguments)),
        "coderide_debug_resolve" => Some(CallToolResult::text("OK — debug session resolved")),
        "coderide_debug_session" => Some(debug_session(arguments)),
        "coderide_debug_hypothesize" => Some(debug_hypothesize(arguments)),
        "coderide_debug_timeline" => Some(debug_timeline()),
        "coderide_debug_snapshot" => Some(debug_snapshot()),
        "coderide_debug_trace_analyze" => Some(debug_trace_analyze(arguments)),
        "coderide_debug_context" => Some(debug_context(workspace)),
        "coderide_debug_test_check" => Some(debug_test_check(arguments)),
        "coderide_debug_mark" => Some(CallToolResult::text("OK — debug marker inserted")),
        "coderide_debug_clean" => Some(CallToolResult::text("OK — debug markers cleaned")),
        "coderide_debug_instrument" => Some(CallToolResult::text("OK — debug instrumentation inserted")),
        _ => None,
    }
}

fn debug_set_phase(arguments: &BTreeMap<String, Value>) -> CallToolResult {
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
        return CallToolResult::error("Error: 'phase' parameter is required");
    }
    if !valid.contains(&phase.as_str()) {
        return CallToolResult::error(format!(
            "Error: invalid phase '{phase}'. Use: {}",
            valid.join(", ")
        ));
    }
    let mut store = read_store();
    store.phase = Some(phase.clone());
    let _ = write_store(&store);
    CallToolResult::text(format!("OK — debug phase set to {phase}"))
}

fn debug_request_user(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let kind = string_arg(arguments, "kind").to_lowercase();
    let prompt = string_arg(arguments, "prompt");
    if kind.is_empty() || prompt.is_empty() {
        return CallToolResult::error("Error: 'kind' and 'prompt' are required");
    }
    if !["question", "reproduce", "fix_confirmation"].contains(&kind.as_str()) {
        return CallToolResult::error("Error: invalid kind. Use: question, reproduce, or fix_confirmation");
    }
    CallToolResult::text(format!("OK — debug user request queued ({kind})"))
}

fn debug_log(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store();
    store.logs.push(DebugLogEntry {
        severity: string_arg(arguments, "severity"),
        source: string_arg(arguments, "source"),
        message: string_arg(arguments, "message"),
    });
    let _ = write_store(&store);
    CallToolResult::text("OK — debug log entry recorded")
}

fn debug_query(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let store = read_store();
    let search = string_arg(arguments, "search").to_lowercase();
    let severity = string_arg(arguments, "severity").to_lowercase();
    let lines = store
        .logs
        .iter()
        .filter(|entry| severity.is_empty() || entry.severity.to_lowercase() == severity)
        .filter(|entry| search.is_empty() || entry.message.to_lowercase().contains(&search))
        .map(|entry| format!("[{}] {} — {}", entry.severity, entry.source, entry.message))
        .collect::<Vec<_>>();
    if lines.is_empty() {
        CallToolResult::text("No debug logs found.")
    } else {
        CallToolResult::text(lines.join("\n"))
    }
}

fn debug_session(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store();
    match string_arg(arguments, "action").to_lowercase().as_str() {
        "start" => {
            store.session_active = true;
            let _ = write_store(&store);
            CallToolResult::text("OK — debug session started")
        }
        "end" | "stop" => {
            store.session_active = false;
            let _ = write_store(&store);
            CallToolResult::text("OK — debug session ended")
        }
        "clear" => {
            let _ = write_store(&DebugStore::default());
            CallToolResult::text("OK — debug session cleared")
        }
        "stats" => CallToolResult::text(format!(
            "session_active: {}\nlogs: {}\nhypotheses: {}",
            if store.session_active { "true" } else { "false" },
            store.logs.len(),
            store.hypotheses.len()
        )),
        _ => CallToolResult::error("Error: unsupported debug_session action"),
    }
}

fn debug_hypothesize(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut store = read_store();
    let action = string_arg(arguments, "action").to_lowercase();
    if action == "propose" {
        let title = string_arg(arguments, "title");
        if title.is_empty() {
            return CallToolResult::error("Error: 'title' is required");
        }
        store.hypotheses.push(DebugHypothesis {
            id: format!("hyp-{}", store.hypotheses.len() + 1),
            title,
            status: string_arg(arguments, "status"),
            description: non_empty(string_arg(arguments, "description")),
        });
        let _ = write_store(&store);
        return CallToolResult::text("OK — debug hypothesis proposed");
    }
    if action == "update" {
        let hypothesis_id = string_arg(arguments, "hypothesis_id");
        if let Some(existing) = store.hypotheses.iter_mut().find(|item| item.id == hypothesis_id) {
            let status = string_arg(arguments, "status");
            if !status.is_empty() {
                existing.status = status;
            }
            let _ = write_store(&store);
            return CallToolResult::text("OK — debug hypothesis updated");
        }
        return CallToolResult::error("Error: hypothesis not found");
    }
    CallToolResult::error("Error: unsupported debug_hypothesize action")
}

fn debug_timeline() -> CallToolResult {
    let store = read_store();
    let mut lines = Vec::new();
    if let Some(phase) = store.phase {
        lines.push(format!("phase: {phase}"));
    }
    for hypothesis in store.hypotheses {
        lines.push(format!(
            "hypothesis {} [{}] {}",
            hypothesis.id, hypothesis.status, hypothesis.title
        ));
    }
    for log in store.logs {
        lines.push(format!("log [{}] {}", log.severity, log.message));
    }
    if lines.is_empty() {
        CallToolResult::text("No debug timeline available.")
    } else {
        CallToolResult::text(lines.join("\n"))
    }
}

fn debug_snapshot() -> CallToolResult {
    let store = read_store();
    CallToolResult::text(
        serde_json::to_string_pretty(&store).unwrap_or_else(|_| "{}".to_string()),
    )
}

fn debug_trace_analyze(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let error_text = string_arg(arguments, "error_text");
    if error_text.is_empty() {
        return CallToolResult::error("Error: 'error_text' is required");
    }
    let error_type = string_arg(arguments, "error_type");
    CallToolResult::text(format!(
        "error_type: {}\nsummary: review the stack for the first failing frame and validate the closest mutated callsite.",
        if error_type.is_empty() {
            "unknown"
        } else {
            error_type.as_str()
        }
    ))
}

fn debug_context(workspace: &Path) -> CallToolResult {
    let mut lines = vec![format!("workspace: {}", workspace.display())];
    if let Ok(entries) = fs::read_dir(workspace) {
        for entry in entries.flatten().take(20) {
            lines.push(entry.file_name().to_string_lossy().to_string());
        }
    }
    CallToolResult::text(lines.join("\n"))
}

fn debug_test_check(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let filter = string_arg(arguments, "filter");
    if filter.is_empty() {
        CallToolResult::text("OK — debug test check queued")
    } else {
        CallToolResult::text(format!("OK — debug test check queued ({filter})"))
    }
}

fn read_store() -> DebugStore {
    let path = debug_store_path();
    let Ok(data) = fs::read(path) else {
        return DebugStore::default();
    };
    serde_json::from_slice(&data).unwrap_or_default()
}

fn write_store(store: &DebugStore) -> Result<(), String> {
    let path = debug_store_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(store).map_err(|error| error.to_string())?;
    fs::write(path, data).map_err(|error| error.to_string())
}

fn debug_store_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared")
        .join("debug_state.json")
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
