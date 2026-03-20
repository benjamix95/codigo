use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadProviderRegistryEntry {
    pub id: String,
    pub is_authenticated: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadProviderSelectionRequest {
    pub schema_version: i32,
    pub conversation_mode: Option<String>,
    pub preferred_provider_id: Option<String>,
    pub current_provider_id: Option<String>,
    pub selected_provider_id: Option<String>,
    pub registry_selected_provider_id: Option<String>,
    #[serde(default)]
    pub registry_providers: Vec<ThreadProviderRegistryEntry>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadProviderSelectionError {
    pub code: String,
    pub message: String,
}

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadProviderSelectionResponse {
    pub schema_version: i32,
    pub error: Option<ThreadProviderSelectionError>,
    pub effective_mode: Option<String>,
    pub resolved_provider_id: Option<String>,
    pub missing_bound_provider_id: Option<String>,
}

impl ThreadProviderSelectionResponse {
    pub fn success(
        effective_mode: &str,
        resolved_provider_id: Option<String>,
        missing_bound_provider_id: Option<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            error: None,
            effective_mode: Some(effective_mode.to_string()),
            resolved_provider_id,
            missing_bound_provider_id,
        }
    }

    pub fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(ThreadProviderSelectionError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            effective_mode: None,
            resolved_provider_id: None,
            missing_bound_provider_id: None,
        }
    }
}
