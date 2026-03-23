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
pub struct MainChatRuntimeProviderRegistryEntry {
    pub id: String,
    #[serde(default)]
    pub is_authenticated: bool,
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

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeTransportRequest {
    pub schema_version: i32,
    pub selected_provider_id: Option<String>,
    pub fallback_selected_provider_id: Option<String>,
    pub coder_mode: Option<String>,
    #[serde(default)]
    pub should_run_plan_inline: bool,
    #[serde(default)]
    pub force_plan_inline: bool,
    pub prefer_code_review_runtime_provider: Option<bool>,
    pub plan_mode_backend: String,
    pub code_review_execution_backend: String,
    pub openai_api_key: String,
    pub openai_model: String,
    pub anthropic_api_key: String,
    pub anthropic_model: String,
    pub google_api_key: String,
    pub google_model: String,
    pub codex_model_override: String,
    pub codex_sandbox: String,
    #[serde(default)]
    pub codex_session_full_access: bool,
    pub claude_model: String,
    #[serde(default)]
    pub claude_allowed_tools: Vec<String>,
    pub gemini_model_override: String,
    #[serde(default)]
    pub registry_providers: Vec<MainChatRuntimeProviderRegistryEntry>,
    #[serde(default)]
    pub codex_cli_accounts: Vec<MainChatCLIAccountSnapshot>,
    #[serde(default)]
    pub claude_cli_accounts: Vec<MainChatCLIAccountSnapshot>,
    #[serde(default)]
    pub gemini_cli_accounts: Vec<MainChatCLIAccountSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeTransportResponse {
    pub schema_version: i32,
    pub error: Option<MainChatProviderBridgeError>,
    pub provider_id: Option<String>,
    pub backend: Option<MainChatProviderBackend>,
    pub model: Option<String>,
    pub api_key: Option<String>,
    pub base_url: Option<String>,
    #[serde(default)]
    pub extra_headers: BTreeMap<String, String>,
    pub codex_sandbox: Option<String>,
    #[serde(default)]
    pub codex_session_full_access: bool,
    #[serde(default)]
    pub claude_allowed_tools: Vec<String>,
    #[serde(default)]
    pub read_only_plan: bool,
    #[serde(default)]
    pub is_authenticated: bool,
    #[serde(default)]
    pub native_image_attachment: bool,
    #[serde(default)]
    pub native_document_attachment: bool,
    #[serde(default)]
    pub native_file_attachment: bool,
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

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderSessionPollRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub timeout_ms: i32,
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

impl MainChatRuntimeTransportResponse {
    pub fn success(
        provider_id: String,
        backend: MainChatProviderBackend,
        model: Option<String>,
        api_key: Option<String>,
        base_url: Option<String>,
        extra_headers: BTreeMap<String, String>,
        codex_sandbox: Option<String>,
        codex_session_full_access: bool,
        claude_allowed_tools: Vec<String>,
        read_only_plan: bool,
        is_authenticated: bool,
        native_image_attachment: bool,
        native_document_attachment: bool,
        native_file_attachment: bool,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            provider_id: Some(provider_id),
            backend: Some(backend),
            model,
            api_key,
            base_url,
            extra_headers,
            codex_sandbox,
            codex_session_full_access,
            claude_allowed_tools,
            read_only_plan,
            is_authenticated,
            native_image_attachment,
            native_document_attachment,
            native_file_attachment,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatProviderBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            provider_id: None,
            backend: None,
            model: None,
            api_key: None,
            base_url: None,
            extra_headers: BTreeMap::new(),
            codex_sandbox: None,
            codex_session_full_access: false,
            claude_allowed_tools: Vec::new(),
            read_only_plan: false,
            is_authenticated: false,
            native_image_attachment: false,
            native_document_attachment: false,
            native_file_attachment: false,
        }
    }
}
