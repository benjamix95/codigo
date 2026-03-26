use crate::file_lock::{with_file_lock, LockMode};
use serde_json::Value;
use solocode_rust_core::review_mcp::models::{
    BugHunterSnapshotRecord, CommandRecord, PatchRecord, ReviewSnapshotRecord,
};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub fn read_review_snapshots() -> Vec<Value> {
    read_json_objects(&code_review_sessions_dir())
}

pub fn read_review_snapshot(session_id: &str) -> Option<Value> {
    let path = code_review_sessions_dir().join(format!("{session_id}.json"));
    read_json_value(&path)
}

pub fn read_bughunter_snapshots() -> Vec<Value> {
    read_json_objects(&bughunter_runs_dir())
}

pub fn read_bughunter_snapshot(run_id: &str) -> Option<Value> {
    let path = bughunter_runs_dir().join(format!("{run_id}.json"));
    read_json_value(&path)
}

pub fn read_review_commands() -> Vec<CommandRecord> {
    read_command_records(&code_review_commands_path())
}

pub fn write_review_commands(commands: &[CommandRecord]) -> Result<(), String> {
    write_json(&code_review_commands_path(), commands)
}

pub fn read_bughunter_commands() -> Vec<CommandRecord> {
    read_command_records(&bughunter_commands_path())
}

pub fn write_bughunter_commands(commands: &[CommandRecord]) -> Result<(), String> {
    write_json(&bughunter_commands_path(), commands)
}

pub fn make_review_snapshot_record(value: &Value) -> Option<ReviewSnapshotRecord> {
    let findings = value.get("findings")?.as_array()?.clone();
    let candidates = value
        .get("candidates")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let patches = value
        .get("patches")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    Some(ReviewSnapshotRecord {
        session_id: string_field(value, "sessionId")?,
        conversation_id: optional_string_field(value, "conversationId"),
        phase: string_field(value, "phase").unwrap_or_else(|| "idle".to_string()),
        stage: string_field(value, "stage").unwrap_or_else(|| "idle".to_string()),
        findings_count: findings.len() as i32,
        open_findings_count: findings
            .iter()
            .filter(|item| {
                string_field(item, "status").unwrap_or_else(|| "open".to_string()) == "open"
            })
            .count() as i32,
        current_round: int_field(value, "currentRound").unwrap_or(0) as i32,
        active_worker_count: int_field(value, "activeWorkerCount").unwrap_or(0) as i32,
        scope_type: value
            .get("scope")
            .and_then(|scope| optional_string_field(scope, "type")),
        scope_ref: value
            .get("scope")
            .and_then(|scope| optional_string_field(scope, "ref")),
        started_at_reference_seconds: date_field(value, "startedAt").map(reference_seconds),
        updated_at_reference_seconds: date_field(value, "lastUpdatedAt")
            .or_else(|| date_field(value, "updatedAt"))
            .map(reference_seconds)
            .unwrap_or_else(reference_seconds_now),
        is_active: is_active_review_phase(&string_field(value, "phase").unwrap_or_default()),
        finding_ids: findings
            .iter()
            .filter_map(|item| optional_string_field(item, "id"))
            .collect(),
        candidate_ids: candidates
            .iter()
            .filter_map(|item| optional_string_field(item, "id"))
            .collect(),
        patches: patches
            .iter()
            .filter_map(|item| {
                Some(PatchRecord {
                    id: string_field(item, "id")?,
                    finding_id: string_field(item, "findingId")
                        .or_else(|| string_field(item, "finding_id"))?,
                    verify_status: string_field(item, "verifyStatus")
                        .or_else(|| string_field(item, "verify_status"))?,
                    risk_score: float_field(item, "riskScore").unwrap_or(0.0),
                })
            })
            .collect(),
    })
}

pub fn make_bughunter_snapshot_record(value: &Value) -> Option<BugHunterSnapshotRecord> {
    Some(BugHunterSnapshotRecord {
        run_id: string_field(value, "runId")?,
        conversation_id: optional_string_field(value, "conversationId"),
        review_session_id: optional_string_field(value, "reviewSessionId"),
        source_kind: string_field(value, "sourceKind")?,
        trigger_kind: string_field(value, "triggerKind")?,
        git_root: string_field(value, "gitRoot").unwrap_or_default(),
        branch_name: optional_string_field(value, "branchName"),
        primary_commit: optional_string_field(value, "primaryCommit"),
        related_commits: value
            .get("relatedCommits")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(Value::as_str)
                    .map(ToString::to_string)
                    .collect()
            })
            .unwrap_or_default(),
        status: string_field(value, "status")?,
        last_message: optional_string_field(value, "lastMessage"),
        verified_findings_count: int_field(value, "verifiedFindingsCount").unwrap_or(0) as i32,
        candidate_findings_count: int_field(value, "candidateFindingsCount").unwrap_or(0) as i32,
        last_revalidation_verdict: optional_string_field(value, "lastRevalidationVerdict"),
        security_gate_ready: value.get("securityGateReady").and_then(Value::as_bool),
    })
}

pub fn redacted_label(file_path: &str) -> String {
    let ext = Path::new(file_path)
        .extension()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty())
        .unwrap_or("file");
    format!("redacted-{ext}-file-{:08x}", stable_hash(file_path))
}

pub fn redacted_summary(severity: &str, category: &str) -> String {
    format!("Redacted {severity} {category} finding")
}

pub fn reference_seconds_now() -> f64 {
    reference_seconds(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64(),
    )
}

pub fn reference_seconds(unix_seconds: f64) -> f64 {
    unix_seconds - 978_307_200.0
}

/// Ordinamento stabile per “sessione più recente” (evita confronto lessicografico su stringhe data).
pub fn json_recency_rank(value: &Value) -> (u64, i64) {
    let secs = date_field(value, "lastUpdatedAt")
        .or_else(|| date_field(value, "updatedAt"))
        .unwrap_or(0.0);
    let nanos = (secs * 1e9).clamp(0.0, u64::MAX as f64) as u64;
    let seq = int_field(value, "mutationSequence").unwrap_or(0);
    (nanos, seq)
}

pub fn shared_dir() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("CoderIDE")
        .join("mcp-shared")
}

pub fn code_review_sessions_dir() -> PathBuf {
    shared_dir().join("code-review").join("sessions")
}

pub fn code_review_commands_path() -> PathBuf {
    shared_dir().join("code-review").join("commands.json")
}

pub fn bughunter_runs_dir() -> PathBuf {
    shared_dir().join("bughunter").join("runs")
}

pub fn bughunter_commands_path() -> PathBuf {
    shared_dir().join("bughunter").join("commands.json")
}

fn read_json_objects(dir: &Path) -> Vec<Value> {
    fs::read_dir(dir)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| read_json_value(&entry.path()))
        .collect()
}

fn read_json_value(path: &Path) -> Option<Value> {
    let data = fs::read(path).ok()?;
    serde_json::from_slice(&data).ok()
}

fn read_command_records(path: &Path) -> Vec<CommandRecord> {
    let Ok(data) = fs::read(path) else {
        return Vec::new();
    };
    serde_json::from_slice(&data).unwrap_or_default()
}

fn write_json<T: serde::Serialize + ?Sized>(path: &Path, value: &T) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let data = serde_json::to_vec_pretty(value).map_err(|error| error.to_string())?;
    let lock_result = with_file_lock(path, LockMode::Exclusive, || {
        // Atomic write: temp file + rename to prevent partial writes.
        let tmp_path = path.with_extension("json.tmp");
        fs::write(&tmp_path, &data).map_err(|error| error.to_string())?;
        fs::rename(&tmp_path, path).map_err(|error| error.to_string())
    });
    match lock_result {
        Ok(inner) => Ok(inner),
        Err(e) => Err(e),
    }
}

fn string_field(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(|text| text.to_string())
}

fn optional_string_field(value: &Value, key: &str) -> Option<String> {
    string_field(value, key).filter(|text| !text.trim().is_empty())
}

fn int_field(value: &Value, key: &str) -> Option<i64> {
    value.get(key).and_then(Value::as_i64)
}

fn float_field(value: &Value, key: &str) -> Option<f64> {
    value.get(key).and_then(Value::as_f64)
}

fn date_field(value: &Value, key: &str) -> Option<f64> {
    value
        .get(key)
        .and_then(Value::as_str)
        .and_then(|text| chrono_like_to_unix(text))
}

fn chrono_like_to_unix(text: &str) -> Option<f64> {
    if text.is_empty() {
        return None;
    }
    // Fast path: RFC 3339 covers most ISO 8601 strings we produce.
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(text) {
        return Some(dt.timestamp() as f64 + dt.timestamp_subsec_nanos() as f64 / 1e9);
    }
    // Fallback: naive formats (assume UTC when no timezone present).
    for fmt in &[
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%S%.f",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S%.f",
    ] {
        if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(text, fmt) {
            return Some(dt.and_utc().timestamp() as f64 + dt.and_utc().timestamp_subsec_nanos() as f64 / 1e9);
        }
    }
    // Last resort: raw f64 (already a Unix timestamp).
    text.parse::<f64>().ok()
}

fn stable_hash(input: &str) -> u32 {
    let mut hash: u32 = 2_166_136_261;
    for byte in input.as_bytes() {
        hash ^= *byte as u32;
        hash = hash.wrapping_mul(16_777_619);
    }
    hash
}

fn is_active_review_phase(phase: &str) -> bool {
    !matches!(phase, "completed" | "failed" | "idle")
}
