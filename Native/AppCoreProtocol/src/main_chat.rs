use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatArtifactKind {
    Mermaid,
    Commands,
    Files,
    Status,
    Plan,
    ToolTrace,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatEventKind {
    TurnStarted,
    TurnCompleted,
    TurnFailed,
    TextDelta,
    TextReplace,
    ReasoningDelta,
    MermaidArtifact,
    ToolTraceArtifact,
    CommandsArtifact,
    FilesArtifact,
    TodoSnapshot,
    StatusBadge,
    PlanArtifact,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatProviderChunkKind {
    Started,
    TextDelta,
    TextReplace,
    Completed,
    Error,
    ReasoningDelta,
    MermaidArtifact,
    ToolTraceArtifact,
    CommandsArtifact,
    FilesArtifact,
    StatusBadge,
    PlanArtifact,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatArtifact {
    pub id: String,
    pub kind: MainChatArtifactKind,
    pub title: String,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub items: Vec<String>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
    #[serde(default = "default_true")]
    pub is_collapsible: bool,
    #[serde(default)]
    pub is_collapsed_by_default: bool,
}

impl Default for MainChatArtifact {
    fn default() -> Self {
        Self {
            id: String::new(),
            kind: MainChatArtifactKind::Status,
            title: String::new(),
            text: String::new(),
            items: Vec::new(),
            metadata: BTreeMap::new(),
            is_collapsible: true,
            is_collapsed_by_default: false,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTurnState {
    pub conversation_id: String,
    pub assistant_message_id: String,
    pub turn_id: String,
    pub provider_id: Option<String>,
    #[serde(default)]
    pub sequence: i32,
    #[serde(default)]
    pub is_streaming: bool,
    pub started_at: Option<f64>,
    pub completed_at: Option<f64>,
    pub updated_at: Option<f64>,
    pub status: String,
    #[serde(default)]
    pub ordered_text_stream_ids: Vec<String>,
    #[serde(default)]
    pub text_by_stream_id: BTreeMap<String, String>,
    #[serde(default)]
    pub reasoning_by_group_id: BTreeMap<String, String>,
    #[serde(default)]
    pub artifacts: Vec<MainChatArtifact>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatEvent {
    pub id: String,
    pub conversation_id: String,
    pub assistant_message_id: String,
    pub turn_id: String,
    pub sequence: i32,
    pub source: String,
    pub kind: MainChatEventKind,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
    pub timestamp: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatActionRequest {
    pub schema_version: i32,
    pub action: String,
    pub state: MainChatTurnState,
    pub timestamp: Option<f64>,
    pub status: Option<String>,
    pub detail: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStartRequest {
    pub schema_version: i32,
    pub state: MainChatTurnState,
    pub timestamp: f64,
    pub provider_id: Option<String>,
    pub status: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReduceEventRequest {
    pub schema_version: i32,
    pub state: MainChatTurnState,
    pub event: MainChatEvent,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatFinishRequest {
    pub schema_version: i32,
    pub state: MainChatTurnState,
    pub timestamp: f64,
    pub status: Option<String>,
    pub detail: Option<String>,
    pub was_cancelled: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderChunk {
    pub kind: MainChatProviderChunkKind,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
    pub timestamp: Option<f64>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatProviderStreamRequest {
    pub schema_version: i32,
    pub state: MainChatTurnState,
    pub source: String,
    #[serde(default)]
    pub chunks: Vec<MainChatProviderChunk>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatBridgeError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatRuntimeResponse {
    pub schema_version: i32,
    pub error: Option<MainChatBridgeError>,
    pub state: Option<MainChatTurnState>,
    #[serde(default)]
    pub emitted_events: Vec<MainChatEvent>,
}

impl MainChatRuntimeResponse {
    pub fn success(state: MainChatTurnState) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            emitted_events: Vec::new(),
        }
    }

    pub fn success_with_events(state: MainChatTurnState, emitted_events: Vec<MainChatEvent>) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            emitted_events,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            state: None,
            emitted_events: Vec::new(),
        }
    }
}

fn default_true() -> bool {
    true
}
