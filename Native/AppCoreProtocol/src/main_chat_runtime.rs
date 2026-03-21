use crate::main_chat::{MainChatBridgeError, MainChatEvent, MainChatTurnState};
use crate::main_chat_provider::MainChatProviderEvent;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatRuntimeMode {
    Agent,
    DirectStream,
    Plan,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatPlanPhase {
    Idle,
    Analyzing,
    Questioning,
    Generating,
    ProposalReady,
    ReadyToBuild,
    Building,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatPlanningStateKind {
    Idle,
    AwaitingClarification,
    AwaitingChoice,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatDirectStreamSnapshot {
    pub first_event_timeout_sec: i32,
    pub activity_timeout_sec: i32,
    pub max_initial_retries: i32,
    pub max_stall_retries: i32,
    pub initial_retry_count: i32,
    pub stall_retry_count: i32,
    pub has_received_any_event: bool,
    pub emitted_first_text: bool,
    pub stream_started_at: Option<f64>,
    pub last_event_at: Option<f64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatPlanSnapshot {
    pub phase: Option<MainChatPlanPhase>,
    pub planning_state_kind: Option<MainChatPlanningStateKind>,
    pub clarification_questions: Option<String>,
    pub proposal_content: Option<String>,
    #[serde(default)]
    pub option_full_texts: Vec<String>,
    #[serde(default)]
    pub user_request: String,
    #[serde(default)]
    pub analysis_context: String,
    #[serde(default)]
    pub clarification_answers: String,
    #[serde(default)]
    pub clarification_cycles: i32,
    #[serde(default)]
    pub question_epoch: i32,
    #[serde(default)]
    pub should_run_inline: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeOutput {
    pub chat_content_override: Option<String>,
    #[serde(default)]
    pub should_hide_plan_markdown: bool,
    #[serde(default)]
    pub should_open_plan_panel: bool,
    #[serde(default)]
    pub should_finalize_stream: bool,
    #[serde(default)]
    pub should_retry_poll: bool,
    pub follow_up_prompt: Option<String>,
    pub generated_prompt: Option<String>,
    pub terminal_error: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeSnapshot {
    pub turn_state: MainChatTurnState,
    pub mode: Option<MainChatRuntimeMode>,
    pub direct_stream: Option<MainChatDirectStreamSnapshot>,
    pub plan: Option<MainChatPlanSnapshot>,
    pub output: Option<MainChatRuntimeOutput>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeActionRequest {
    pub schema_version: i32,
    pub action: String,
    pub snapshot: MainChatRuntimeSnapshot,
    pub timestamp: Option<f64>,
    pub provider_id: Option<String>,
    pub status: Option<String>,
    pub detail: Option<String>,
    pub text: Option<String>,
    pub questions: Option<String>,
    pub plan_content: Option<String>,
    #[serde(default)]
    pub option_full_texts: Vec<String>,
    pub should_run_inline: Option<bool>,
    pub is_initial_poll: Option<bool>,
    pub event_kind: Option<String>,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeActionResponse {
    pub schema_version: i32,
    pub error: Option<MainChatBridgeError>,
    pub runtime_snapshot: Option<MainChatRuntimeSnapshot>,
    #[serde(default)]
    pub emitted_events: Vec<MainChatEvent>,
}

impl MainChatRuntimeActionResponse {
    pub fn success(snapshot: MainChatRuntimeSnapshot) -> Self {
        Self {
            schema_version: 1,
            error: None,
            runtime_snapshot: Some(snapshot),
            emitted_events: Vec::new(),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            runtime_snapshot: None,
            emitted_events: Vec::new(),
        }
    }
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatRuntimeUIEventKind {
    Started,
    TextDelta,
    TextReplace,
    Raw,
    Completed,
    Error,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeUIEvent {
    pub kind: MainChatRuntimeUIEventKind,
    #[serde(default)]
    pub text: String,
    pub raw_type: Option<String>,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeProviderPollRequest {
    pub schema_version: i32,
    pub session_id: String,
    pub provider_id: String,
    pub snapshot: MainChatRuntimeSnapshot,
    #[serde(default)]
    pub timeout_ms: i32,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeProviderPollResponse {
    pub schema_version: i32,
    pub error: Option<MainChatBridgeError>,
    pub runtime_snapshot: Option<MainChatRuntimeSnapshot>,
    #[serde(default)]
    pub ui_events: Vec<MainChatRuntimeUIEvent>,
    #[serde(default)]
    pub provider_events: Vec<MainChatProviderEvent>,
    #[serde(default)]
    pub is_terminal: bool,
    #[serde(default)]
    pub did_timeout: bool,
}

impl MainChatRuntimeProviderPollResponse {
    pub fn success(
        runtime_snapshot: MainChatRuntimeSnapshot,
        ui_events: Vec<MainChatRuntimeUIEvent>,
        provider_events: Vec<MainChatProviderEvent>,
        is_terminal: bool,
        did_timeout: bool,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            runtime_snapshot: Some(runtime_snapshot),
            ui_events,
            provider_events,
            is_terminal,
            did_timeout,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            runtime_snapshot: None,
            ui_events: Vec::new(),
            provider_events: Vec::new(),
            is_terminal: false,
            did_timeout: false,
        }
    }
}
