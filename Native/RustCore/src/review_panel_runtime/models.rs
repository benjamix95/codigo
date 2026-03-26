use crate::review_models::ReviewCoreErrorPayload;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRuntimeStateSnapshot {
    pub selected_tab: String,
    pub panel_session_id: Option<String>,
    pub selected_finding_id: Option<String>,
    pub selected_historical_finding_id: Option<String>,
    #[serde(default)]
    pub immersive_finding_workspace_id: Option<String>,
    pub active_chat_thread_id: Option<String>,
    pub is_running: bool,
    pub run_started_at: Option<f64>,
    pub frozen_timer_text: Option<String>,
    pub last_error: Option<String>,
    pub chat_messages: Vec<Value>,
    pub is_chat_processing: bool,
    pub chat_started_at: Option<f64>,
    #[serde(default)]
    pub response_message_ids: BTreeMap<String, String>,
    #[serde(default)]
    pub finished_review_run_activity_ids: Vec<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRuntimeEventEnvelope {
    pub kind: String,
    pub text: Option<String>,
    pub event_type: Option<String>,
    #[serde(default)]
    pub payload: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRunStartRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub selected_tab_on_start: String,
    pub started_at: Option<f64>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelEventReduceRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub activity_message_id: String,
    pub suggested_response_message_id: Option<String>,
    pub suggested_verdict_message_id: Option<String>,
    pub timestamp: Option<f64>,
    pub event: ReviewPanelRuntimeEventEnvelope,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRunFinishRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub selected_tab_on_finish: String,
    pub finished_at: Option<f64>,
    pub snapshot_phase: Option<String>,
    pub snapshot_last_error: Option<String>,
    pub error_message: Option<String>,
    pub was_cancelled: bool,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelChatStartRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub assistant_message_id: String,
    pub started_at: Option<f64>,
    pub message_timestamp: Option<f64>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelChatFinishRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub assistant_message_id: Option<String>,
    pub finished_at: Option<f64>,
    pub error_message: Option<String>,
    pub was_cancelled: bool,
    pub fallback_content: Option<String>,
    pub finish_all_streaming: bool,
    pub suggested_verdict_message_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelPromptRequest {
    pub schema_version: i32,
    pub prompt_kind: String,
    pub scope_tag: Option<String>,
    pub scope_kind: Option<String>,
    pub current_branch: Option<String>,
    pub branch_name: Option<String>,
    #[serde(default)]
    pub commits: Vec<String>,
    #[serde(default)]
    pub selected_modes: Vec<String>,
    #[serde(default)]
    pub scan_depth: Option<String>,
    #[serde(default)]
    pub codebase_file_paths: Vec<String>,
    pub custom_instructions: Option<String>,
    pub user_message: Option<String>,
    pub session_summary: Option<String>,
    pub findings_count: Option<i32>,
    pub open_count: Option<i32>,
    pub active_session_id: Option<String>,
    pub conversation_id: Option<String>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelIntentRequest {
    pub schema_version: i32,
    pub state: ReviewPanelRuntimeStateSnapshot,
    pub intent: String,
    pub value: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRuntimeOutcome {
    pub status: String,
    pub message: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelRuntimeResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub state: Option<ReviewPanelRuntimeStateSnapshot>,
    pub outcome: Option<ReviewPanelRuntimeOutcome>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewPanelPromptResponse {
    pub schema_version: i32,
    pub error: Option<ReviewCoreErrorPayload>,
    pub prompt: Option<String>,
}

impl ReviewPanelRuntimeResponse {
    pub fn success(state: ReviewPanelRuntimeStateSnapshot) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            outcome: None,
        }
    }

    pub fn success_with_outcome(
        state: ReviewPanelRuntimeStateSnapshot,
        status: &str,
        message: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            state: Some(state),
            outcome: Some(ReviewPanelRuntimeOutcome {
                status: status.to_string(),
                message,
            }),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            state: None,
            outcome: None,
        }
    }
}

impl ReviewPanelPromptResponse {
    pub fn success(prompt: String) -> Self {
        Self {
            schema_version: 1,
            error: None,
            prompt: Some(prompt),
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ReviewCoreErrorPayload::new(code, message)),
            prompt: None,
        }
    }
}
