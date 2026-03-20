use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningBlock {
    pub id: String,
    pub text: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningSegment {
    pub id: String,
    pub kind: String,
    pub text: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningState {
    #[serde(default)]
    pub blocks: Vec<MainChatReasoningBlock>,
    pub text: Option<String>,
    #[serde(default)]
    pub segments: Vec<MainChatReasoningSegment>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningRequest {
    pub schema_version: i32,
    pub operation: String,
    pub provider_id: Option<String>,
    pub separate_codex_thinking_messages_enabled: Option<bool>,
    pub event_conversation_id: Option<String>,
    pub selected_conversation_id: Option<String>,
    pub output: Option<String>,
    pub group_id: Option<String>,
    pub state: Option<MainChatReasoningState>,
    pub sequential_streaming_layout_enabled: Option<bool>,
    pub streaming_segment_turn_index: Option<i32>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningBridgeError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatReasoningResponse {
    pub schema_version: i32,
    pub error: Option<MainChatReasoningBridgeError>,
    pub presentation_mode: Option<String>,
    pub is_codex_provider: Option<bool>,
    pub should_update_inline_reasoning_state: Option<bool>,
    pub state: Option<MainChatReasoningState>,
}

impl MainChatReasoningResponse {
    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatReasoningBridgeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            presentation_mode: None,
            is_codex_provider: None,
            should_update_inline_reasoning_state: None,
            state: None,
        }
    }
}
