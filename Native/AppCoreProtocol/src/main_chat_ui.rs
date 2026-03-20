use crate::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanningStateKind, MainChatRuntimeSnapshot,
};
use crate::main_chat_store::{
    MainChatStoreSnapshot, MainChatStoreSubagentCardSnapshot, MainChatStoreTimelineBlockSnapshot,
};
use crate::main_chat_task_runtime::MainChatTaskRuntimeState;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiState {
    pub store_snapshot: MainChatStoreSnapshot,
    pub runtime_snapshot: Option<MainChatRuntimeSnapshot>,
    pub task_runtime_state: Option<MainChatTaskRuntimeState>,
    pub selected_conversation_id: Option<String>,
    #[serde(default)]
    pub draft_text: String,
    #[serde(default)]
    pub plan_panel_visible: bool,
    #[serde(default = "default_true")]
    pub follow_live: bool,
    #[serde(default)]
    pub collapsed_artifact_ids_by_turn: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub auto_todo_runtime_state_by_message: BTreeMap<String, MainChatUiAutoTodoRuntimeState>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiConversationSummary {
    pub id: String,
    pub title: String,
    pub message_count: i32,
    pub last_message_preview: Option<String>,
    pub mode: Option<String>,
    pub preferred_provider_id: Option<String>,
    #[serde(default)]
    pub is_archived: bool,
    #[serde(default)]
    pub is_selected: bool,
    #[serde(default)]
    pub is_loading: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiTimelineBlockSnapshot {
    pub id: String,
    pub kind: String,
    pub title: Option<String>,
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub items: Vec<String>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
    #[serde(default)]
    pub is_collapsible: bool,
    #[serde(default)]
    pub is_collapsed_by_default: bool,
    #[serde(default)]
    pub is_collapsed: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiMessageSnapshot {
    pub id: String,
    pub role: String,
    pub turn_id: Option<String>,
    #[serde(default)]
    pub content: String,
    pub primary_text: Option<String>,
    pub reasoning_text: Option<String>,
    pub turn_status: Option<String>,
    #[serde(default)]
    pub is_streaming: bool,
    #[serde(default)]
    pub timeline_blocks: Vec<MainChatUiTimelineBlockSnapshot>,
    #[serde(default)]
    pub subagent_cards: Vec<MainChatStoreSubagentCardSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiComposerSnapshot {
    #[serde(default)]
    pub draft_text: String,
    #[serde(default)]
    pub can_send: bool,
    #[serde(default)]
    pub can_cancel: bool,
    #[serde(default)]
    pub is_following_live: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiTaskSnapshot {
    #[serde(default)]
    pub is_loading: bool,
    pub started_at: Option<f64>,
    pub status_text: Option<String>,
    pub terminal_error: Option<String>,
    #[serde(default)]
    pub should_retry_poll: bool,
    #[serde(default)]
    pub should_finalize_stream: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiPlanSnapshot {
    #[serde(default)]
    pub is_visible: bool,
    pub phase: Option<MainChatPlanPhase>,
    pub planning_state_kind: Option<MainChatPlanningStateKind>,
    #[serde(default)]
    pub question_epoch: i32,
    pub clarification_questions: Option<String>,
    pub proposal_content: Option<String>,
    pub chosen_path: Option<String>,
    #[serde(default)]
    pub option_full_texts: Vec<String>,
    #[serde(default)]
    pub goal: String,
    #[serde(default)]
    pub step_count: i32,
    #[serde(default)]
    pub should_hide_markdown: bool,
    #[serde(default)]
    pub should_run_inline: bool,
    #[serde(default)]
    pub is_ready_to_build: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiAutoTodoRuntimeState {
    pub todo_id: String,
    pub conversation_id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub active_form: String,
    #[serde(default)]
    pub linked_files: Vec<String>,
    #[serde(default)]
    pub operation_count: i32,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum MainChatUiTodoMutation {
    UpsertRuntimeTodo,
    SetStatus,
    RemoveTodo,
    ClearMessageRuntimeState,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiTodoPatch {
    pub mutation: Option<MainChatUiTodoMutation>,
    pub todo_id: Option<String>,
    pub assistant_message_id: Option<String>,
    pub conversation_id: Option<String>,
    pub provider_id: Option<String>,
    pub title: Option<String>,
    pub status: Option<String>,
    pub priority: Option<String>,
    pub notes: Option<String>,
    pub active_form: Option<String>,
    #[serde(default)]
    pub linked_files: Vec<String>,
    #[serde(default)]
    pub should_emit_trace_update: bool,
    pub timestamp: Option<f64>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiSnapshot {
    pub selected_conversation_id: Option<String>,
    #[serde(default)]
    pub conversations: Vec<MainChatUiConversationSummary>,
    #[serde(default)]
    pub messages: Vec<MainChatUiMessageSnapshot>,
    pub composer: MainChatUiComposerSnapshot,
    pub task: MainChatUiTaskSnapshot,
    pub plan: MainChatUiPlanSnapshot,
    pub follow_up_prompt: Option<String>,
    pub generated_prompt: Option<String>,
    #[serde(default)]
    pub is_empty: bool,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiProjectRequest {
    pub schema_version: i32,
    pub state: MainChatUiState,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiProjectResponse {
    pub schema_version: i32,
    pub error: Option<MainChatUiError>,
    pub snapshot: Option<MainChatUiSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiIntentRequest {
    pub schema_version: i32,
    pub intent: String,
    pub state: MainChatUiState,
    pub conversation_id: Option<String>,
    pub turn_id: Option<String>,
    pub artifact_id: Option<String>,
    pub text: Option<String>,
    pub timestamp: Option<f64>,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatUiIntentResponse {
    pub schema_version: i32,
    pub error: Option<MainChatUiError>,
    pub state: Option<MainChatUiState>,
    pub snapshot: Option<MainChatUiSnapshot>,
    #[serde(default)]
    pub todo_patches: Vec<MainChatUiTodoPatch>,
}

impl MainChatUiProjectResponse {
    pub fn success(snapshot: MainChatUiSnapshot) -> Self {
        Self { schema_version: 1, error: None, snapshot: Some(snapshot) }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatUiError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            snapshot: None,
        }
    }
}

impl MainChatUiIntentResponse {
    pub fn success(state: MainChatUiState, snapshot: MainChatUiSnapshot) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            snapshot: Some(snapshot),
            todo_patches: Vec::new(),
        }
    }

    pub fn success_with_patches(
        state: MainChatUiState,
        snapshot: MainChatUiSnapshot,
        todo_patches: Vec<MainChatUiTodoPatch>,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            snapshot: Some(snapshot),
            todo_patches,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatUiError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            state: None,
            snapshot: None,
            todo_patches: Vec::new(),
        }
    }
}

fn default_true() -> bool {
    true
}

pub fn timeline_block_from_store(
    block: &MainChatStoreTimelineBlockSnapshot,
    is_collapsed: bool,
) -> MainChatUiTimelineBlockSnapshot {
    MainChatUiTimelineBlockSnapshot {
        id: block.id.clone(),
        kind: block.kind.clone(),
        title: block.title.clone(),
        text: block.text.clone(),
        items: block.items.clone(),
        metadata: block.metadata.clone(),
        is_collapsible: block.is_collapsible,
        is_collapsed_by_default: block.is_collapsed_by_default,
        is_collapsed,
    }
}
