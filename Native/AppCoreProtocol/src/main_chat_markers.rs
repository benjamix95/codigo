use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatMarkersRequest {
    pub schema_version: i32,
    pub operation: String,
    pub text: String,
    pub aggressive: Option<bool>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatMarkersError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MainChatMarkersResponse {
    pub schema_version: i32,
    pub error: Option<MainChatMarkersError>,
    pub text: Option<String>,
}

impl MainChatMarkersResponse {
    pub fn success(text: Option<String>) -> Self {
        Self {
            schema_version: 1,
            error: None,
            text,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(MainChatMarkersError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            text: None,
        }
    }
}
