use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MainChatProviderBackend {
    CodexCli,
    ClaudeCli,
    GeminiCli,
    #[default]
    OpenaiApi,
    AnthropicApi,
    GoogleApi,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderAttachment {
    pub kind: String,
    pub file_path: String,
    pub mime_type: Option<String>,
    pub filename: String,
    pub size_bytes: Option<i64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatCLIQuotaSnapshot {
    pub daily_limit_usd: Option<f64>,
    pub weekly_limit_usd: Option<f64>,
    pub monthly_limit_usd: Option<f64>,
    pub daily_token_limit: Option<i64>,
    pub weekly_token_limit: Option<i64>,
    pub monthly_token_limit: Option<i64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatCLIHealthSnapshot {
    pub cooldown_until: Option<f64>,
    pub last_error_code: Option<String>,
    #[serde(default)]
    pub consecutive_failures: i32,
    #[serde(default)]
    pub is_exhausted_locally: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatCLIAccountSnapshot {
    pub id: String,
    pub provider: String,
    pub label: String,
    #[serde(default)]
    pub is_enabled: bool,
    #[serde(default)]
    pub is_authenticated: bool,
    #[serde(default)]
    pub priority: i32,
    pub profile_path: String,
    #[serde(default)]
    pub env_overrides: BTreeMap<String, String>,
    pub quota: MainChatCLIQuotaSnapshot,
    pub health: MainChatCLIHealthSnapshot,
    pub created_at: Option<f64>,
    pub updated_at: Option<f64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionConfig {
    pub provider_id: String,
    pub display_name: String,
    pub backend: MainChatProviderBackend,
    pub workspace_path: String,
    #[serde(default)]
    pub workspace_paths: Vec<String>,
    pub prompt: String,
    pub system_prompt: Option<String>,
    pub context_prompt: Option<String>,
    pub model: Option<String>,
    pub api_key: Option<String>,
    pub base_url: Option<String>,
    pub tool_definitions_json: Option<String>,
    #[serde(default)]
    pub extra_headers: BTreeMap<String, String>,
    pub codex_path: Option<String>,
    pub codex_sandbox: Option<String>,
    pub codex_ask_for_approval: Option<String>,
    pub codex_model_override: Option<String>,
    pub codex_reasoning_effort: Option<String>,
    pub codex_model_provider: Option<String>,
    #[serde(default)]
    pub codex_fast_mode: bool,
    #[serde(default)]
    pub codex_session_full_access: bool,
    #[serde(default)]
    pub codex_prefer_responses_wire_api: bool,
    pub claude_path: Option<String>,
    pub claude_model: Option<String>,
    #[serde(default)]
    pub claude_allowed_tools: Vec<String>,
    pub gemini_cli_path: Option<String>,
    pub gemini_model_override: Option<String>,
    #[serde(default)]
    pub attachments: Vec<MainChatProviderAttachment>,
    #[serde(default)]
    pub cli_accounts: Vec<MainChatCLIAccountSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatProviderEventKind {
    #[default]
    Started,
    TextDelta,
    TextReplace,
    Raw,
    Completed,
    Error,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderEvent {
    pub kind: MainChatProviderEventKind,
    #[serde(default)]
    pub text: String,
    pub raw_type: Option<String>,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionSnapshot {
    pub session_id: String,
    pub provider_id: String,
    pub backend: Option<MainChatProviderBackend>,
    pub status: String,
    pub terminal_error: Option<String>,
    pub active_account_id: Option<String>,
    #[serde(default)]
    pub round_robin_index: i32,
    #[serde(default)]
    pub emitted_event_count: i32,
    pub last_failover_reason: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionStartRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub config: MainChatProviderSessionConfig,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionRequest {
    pub schema_version: i32,
    pub session_id: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderBridgeError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionResponse {
    pub schema_version: i32,
    pub error: Option<MainChatProviderBridgeError>,
    pub snapshot: Option<MainChatProviderSessionSnapshot>,
    #[serde(default)]
    pub events: Vec<MainChatProviderEvent>,
}

impl MainChatProviderSessionResponse {
    pub fn success(snapshot: MainChatProviderSessionSnapshot, events: Vec<MainChatProviderEvent>) -> Self {
        Self {
            schema_version: 1,
            error: None,
            snapshot: Some(snapshot),
            events,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatProviderBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            snapshot: None,
            events: Vec::new(),
        }
    }
}
