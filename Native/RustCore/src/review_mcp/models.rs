use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPToolRequest {
    pub schema_version: i32,
    pub tool_name: String,
    #[serde(default)]
    pub args: HashMap<String, String>,
    #[serde(default)]
    pub review_snapshots: Vec<ReviewSnapshotRecord>,
    pub active_review_snapshot: Option<ReviewSnapshotRecord>,
    #[serde(default)]
    pub review_findings_payload: Vec<HashMap<String, String>>,
    pub review_status_payload: Option<HashMap<String, String>>,
    pub review_outcome_payload: Option<HashMap<String, String>>,
    #[serde(default)]
    pub bughunter_snapshots: Vec<BugHunterSnapshotRecord>,
    pub active_bughunter_snapshot: Option<BugHunterSnapshotRecord>,
    #[serde(default)]
    pub bughunter_findings_payload: Vec<HashMap<String, String>>,
    pub bughunter_cluster_payload: Option<HashMap<String, String>>,
    pub security_gate_payload: Option<HashMap<String, String>>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPCommandQueueRequest {
    pub schema_version: i32,
    pub operation: String,
    pub queue_kind: String,
    #[serde(default)]
    pub commands: Vec<CommandRecord>,
    pub command_id: Option<String>,
    pub action: Option<String>,
    pub session_id: Option<String>,
    pub run_id: Option<String>,
    pub conversation_id: Option<String>,
    pub status: Option<String>,
    pub result_message: Option<String>,
    pub now_reference_seconds: f64,
    #[serde(default)]
    pub payload: HashMap<String, String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandRecord {
    pub id: String,
    pub action: String,
    pub session_id: Option<String>,
    pub run_id: Option<String>,
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub payload: HashMap<String, String>,
    pub created_at_reference_seconds: f64,
    pub updated_at_reference_seconds: f64,
    pub status: String,
    pub result_message: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPIndexRequest {
    pub schema_version: i32,
    #[serde(default)]
    pub review_snapshots: Vec<ReviewSnapshotRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSnapshotRecord {
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub phase: String,
    pub stage: String,
    pub findings_count: i32,
    pub open_findings_count: i32,
    pub current_round: i32,
    pub active_worker_count: i32,
    pub scope_type: Option<String>,
    pub scope_ref: Option<String>,
    pub started_at_reference_seconds: Option<f64>,
    pub updated_at_reference_seconds: f64,
    pub is_active: bool,
    #[serde(default)]
    pub finding_ids: Vec<String>,
    #[serde(default)]
    pub candidate_ids: Vec<String>,
    #[serde(default)]
    pub patches: Vec<PatchRecord>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PatchRecord {
    pub id: String,
    pub finding_id: String,
    pub verify_status: String,
    pub risk_score: f64,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BugHunterSnapshotRecord {
    pub run_id: String,
    #[allow(dead_code)]
    pub conversation_id: Option<String>,
    pub review_session_id: Option<String>,
    pub source_kind: String,
    pub trigger_kind: String,
    pub git_root: String,
    pub branch_name: Option<String>,
    pub primary_commit: Option<String>,
    #[serde(default)]
    pub related_commits: Vec<String>,
    pub status: String,
    pub last_message: Option<String>,
    pub verified_findings_count: i32,
    pub candidate_findings_count: i32,
    pub last_revalidation_verdict: Option<String>,
    pub security_gate_ready: Option<bool>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPToolResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub message: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPCommandQueueResponse {
    pub schema_version: i32,
    pub is_error: bool,
    pub error_message: Option<String>,
    #[serde(default)]
    pub commands: Vec<CommandRecord>,
    #[serde(default)]
    pub claimed_commands: Vec<CommandRecord>,
    pub command: Option<CommandRecord>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewMCPIndexResponse {
    pub schema_version: i32,
    pub latest_session_id: Option<String>,
    #[serde(default)]
    pub latest_session_id_by_conversation: HashMap<String, String>,
    #[serde(default)]
    pub sessions: Vec<ReviewSnapshotIndexRecord>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewSnapshotIndexRecord {
    pub session_id: String,
    pub conversation_id: Option<String>,
    pub phase: String,
    pub stage: String,
    pub findings_count: i32,
    pub open_findings_count: i32,
    pub current_round: i32,
    pub active_worker_count: i32,
    pub scope_type: Option<String>,
    pub scope_ref: Option<String>,
    pub started_at_reference_seconds: Option<f64>,
    pub updated_at_reference_seconds: f64,
    pub is_active: bool,
}

impl ReviewMCPToolResponse {
    pub fn ok(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            message: message.into(),
        }
    }

    pub fn err(message: impl Into<String>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            message: message.into(),
        }
    }
}

impl ReviewMCPCommandQueueResponse {
    pub fn ok(
        commands: Vec<CommandRecord>,
        command: Option<CommandRecord>,
        claimed_commands: Vec<CommandRecord>,
    ) -> Self {
        Self {
            schema_version: 1,
            is_error: false,
            error_message: None,
            commands,
            claimed_commands,
            command,
        }
    }

    pub fn err(message: impl Into<String>, commands: Vec<CommandRecord>) -> Self {
        Self {
            schema_version: 1,
            is_error: true,
            error_message: Some(message.into()),
            commands,
            claimed_commands: Vec::new(),
            command: None,
        }
    }
}

pub fn get_arg<'a>(args: &'a HashMap<String, String>, key: &str) -> &'a str {
    args.get(key).map(String::as_str).unwrap_or("")
}

pub fn trimmed_arg(args: &HashMap<String, String>, key: &str) -> String {
    get_arg(args, key).trim().to_string()
}

pub fn find_patch<'a>(snapshot: &'a ReviewSnapshotRecord, finding_id: &str) -> Option<&'a PatchRecord> {
    snapshot.patches.iter().find(|patch| patch.finding_id == finding_id)
}

pub fn payload_line_map(payload: &HashMap<String, String>, keys: &[&str]) -> Vec<String> {
    keys.iter()
        .filter_map(|key| payload.get(*key).map(|value| format!("{key}: {value}")))
        .collect()
}
