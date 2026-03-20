use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTaskStateSnapshot {
    pub conversation_id: String,
    pub started_at: Option<f64>,
    pub status_text: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTaskRuntimeState {
    #[serde(default)]
    pub task_states: Vec<MainChatTaskStateSnapshot>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTaskRuntimeRequest {
    pub schema_version: i32,
    pub operation: String,
    pub state: MainChatTaskRuntimeState,
    pub conversation_id: Option<String>,
    pub status_text: Option<String>,
    pub started_at: Option<f64>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTaskRuntimeError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatTaskRuntimeResponse {
    pub schema_version: i32,
    pub error: Option<MainChatTaskRuntimeError>,
    pub state: Option<MainChatTaskRuntimeState>,
}

impl MainChatTaskRuntimeResponse {
    pub fn success(state: MainChatTaskRuntimeState) -> Self {
        Self { schema_version: 1, error: None, state: Some(state) }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatTaskRuntimeError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            state: None,
        }
    }
}
