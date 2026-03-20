use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreAttachmentSnapshot {
    pub id: String,
    pub kind: String,
    pub original_name: String,
    pub mime_type: Option<String>,
    pub local_path: String,
    pub size_bytes: Option<i64>,
    pub created_at: Option<f64>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStorePlanAttachmentSnapshot {
    pub history_entry_id: String,
    pub layout_version: i32,
    pub show_expand: bool,
    pub snapshot_title: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreSubagentCardSnapshot {
    pub swarm_id: String,
    pub status: String,
    pub title: String,
    pub detail: String,
    pub summary: Option<String>,
    pub error_count: i32,
    pub warning_count: Option<i32>,
    pub result_preview: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreTimelineBlockSnapshot {
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
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreTurnMetadataSnapshot {
    pub turn_id: String,
    pub provider_id: Option<String>,
    #[serde(default)]
    pub sequence: i32,
    pub status: String,
    pub started_at: Option<f64>,
    pub completed_at: Option<f64>,
    pub updated_at: Option<f64>,
    #[serde(default)]
    pub is_streaming: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreMessageSnapshot {
    pub id: String,
    pub role: String,
    pub content: String,
    pub primary_text_snapshot: Option<String>,
    pub blocks: Option<Vec<MainChatStoreTimelineBlockSnapshot>>,
    pub turn_metadata: Option<MainChatStoreTurnMetadataSnapshot>,
    #[serde(default)]
    pub is_streaming: bool,
    pub image_paths: Option<Vec<String>>,
    pub attachments: Option<Vec<MainChatStoreAttachmentSnapshot>>,
    pub plan_attachment: Option<MainChatStorePlanAttachmentSnapshot>,
    pub reasoning_text: Option<String>,
    pub subagent_cards: Option<Vec<MainChatStoreSubagentCardSnapshot>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStorePlanOptionSnapshot {
    pub id: i32,
    pub title: String,
    pub full_text: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStorePlanStepSnapshot {
    pub id: String,
    pub title: String,
    pub description: String,
    pub target_file: Option<String>,
    pub status: String,
    #[serde(default)]
    pub linked_files: Vec<String>,
    #[serde(default)]
    pub depends_on: Vec<String>,
    #[serde(default)]
    pub notes: String,
    pub updated_at: Option<f64>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStorePlanBoardSnapshot {
    pub goal: String,
    #[serde(default)]
    pub options: Vec<MainChatStorePlanOptionSnapshot>,
    pub chosen_path: Option<String>,
    #[serde(default)]
    pub steps: Vec<MainChatStorePlanStepSnapshot>,
    pub updated_at: Option<f64>,
    pub walkthrough_markdown: Option<String>,
    pub walkthrough_summary: Option<String>,
    pub walkthrough_outcome: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreCheckpointGitStateSnapshot {
    pub git_root_path: String,
    pub git_snapshot_ref: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreCheckpointSnapshot {
    pub id: String,
    pub created_at: Option<f64>,
    pub message_count: i32,
    pub plan_board_snapshot: Option<MainChatStorePlanBoardSnapshot>,
    pub linked_plan_conversation_id: Option<String>,
    pub linked_plan_board_snapshot: Option<MainChatStorePlanBoardSnapshot>,
    #[serde(default)]
    pub git_states: Vec<MainChatStoreCheckpointGitStateSnapshot>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreConversationSnapshot {
    pub id: String,
    pub thread_root_conversation_id: String,
    pub title: String,
    #[serde(default)]
    pub messages: Vec<MainChatStoreMessageSnapshot>,
    pub created_at: Option<f64>,
    pub context_id: Option<String>,
    pub context_folder_path: Option<String>,
    pub mode: Option<String>,
    pub preferred_provider_id: Option<String>,
    pub context_memory_summary_markdown: Option<String>,
    pub context_memory_generated_at: Option<f64>,
    pub context_memory_source_message_count: Option<i32>,
    #[serde(default)]
    pub is_archived: bool,
    #[serde(default)]
    pub is_pinned: bool,
    #[serde(default)]
    pub is_favorite: bool,
    pub last_input_tokens: Option<i32>,
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub ad_hoc_folder_paths: Vec<String>,
    #[serde(default)]
    pub checkpoints: Vec<MainChatStoreCheckpointSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreSnapshot {
    #[serde(default)]
    pub conversations: Vec<MainChatStoreConversationSnapshot>,
    #[serde(default)]
    pub plan_boards: BTreeMap<String, MainChatStorePlanBoardSnapshot>,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreActionRequest {
    pub schema_version: i32,
    pub action: String,
    pub snapshot: MainChatStoreSnapshot,
    pub conversation_id: Option<String>,
    pub message_id: Option<String>,
    pub checkpoint_id: Option<String>,
    pub message_count: Option<i32>,
    pub conversation: Option<MainChatStoreConversationSnapshot>,
    pub message: Option<MainChatStoreMessageSnapshot>,
    pub plan_board: Option<MainChatStorePlanBoardSnapshot>,
    pub checkpoint: Option<MainChatStoreCheckpointSnapshot>,
    pub title: Option<String>,
    pub mode: Option<String>,
    pub provider_id: Option<String>,
    pub context_id: Option<String>,
    pub context_folder_path: Option<String>,
    pub workspace_id: Option<String>,
    pub bool_value: Option<bool>,
    pub int_value: Option<i32>,
    pub text: Option<String>,
    #[serde(default)]
    pub string_list: Vec<String>,
    pub subagent_cards: Option<Vec<MainChatStoreSubagentCardSnapshot>>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreBridgeError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatStoreResponse {
    pub schema_version: i32,
    pub error: Option<MainChatStoreBridgeError>,
    pub snapshot: Option<MainChatStoreSnapshot>,
}

impl MainChatStoreResponse {
    pub fn success(snapshot: MainChatStoreSnapshot) -> Self {
        Self {
            schema_version: 1,
            error: None,
            snapshot: Some(snapshot),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatStoreBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            snapshot: None,
        }
    }
}
