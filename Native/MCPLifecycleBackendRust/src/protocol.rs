use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Deserialize)]
pub struct RequestEnvelope {
    pub id: String,
    pub op: String,
    #[serde(default = "default_payload")]
    pub payload: Value,
}

#[derive(Clone, Debug, Serialize)]
pub struct ResponseEnvelope {
    pub id: String,
    pub ok: bool,
    pub payload: Value,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerConfig {
    pub id: String,
    pub name: String,
    pub command: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListServersRequest {
    #[serde(default)]
    pub servers: Vec<ServerConfig>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthRequest {
    #[serde(default)]
    pub servers: Vec<ServerConfig>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ListToolsRequest {
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallToolRequest {
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
    pub tool_name: String,
    #[serde(default)]
    pub arguments: Map<String, Value>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerActionRequest {
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResourceRequest {
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
    #[serde(default)]
    pub uri: String,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PromptRequest {
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub arguments: Map<String, Value>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchCallItem {
    pub index: usize,
    #[serde(default)]
    pub server_id: Option<String>,
    #[serde(default)]
    pub server_name: Option<String>,
    #[serde(default)]
    pub server: Option<ServerConfig>,
    pub tool_name: String,
    #[serde(default)]
    pub arguments: Map<String, Value>,
}

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchCallRequest {
    #[serde(default)]
    pub calls: Vec<BatchCallItem>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchCallResultItem {
    pub index: usize,
    pub server_id: String,
    pub server_name: String,
    pub content: String,
    pub is_error: bool,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListedServer {
    pub id: String,
    pub name: String,
    pub status: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolDescriptor {
    pub name: String,
    pub description: String,
    pub schema: String,
    pub server_id: String,
    pub server_name: String,
}

impl ResponseEnvelope {
    pub fn ok(id: String, payload: Value) -> Self {
        Self {
            id,
            ok: true,
            payload,
            error: None,
        }
    }

    pub fn err(id: String, message: impl Into<String>) -> Self {
        Self {
            id,
            ok: false,
            payload: Value::Object(Map::new()),
            error: Some(message.into()),
        }
    }
}

impl ServerConfig {
    pub fn validate(&self) -> Result<(), String> {
        if self.id.trim().is_empty() {
            return Err("server.id is required".to_string());
        }
        if self.name.trim().is_empty() {
            return Err("server.name is required".to_string());
        }
        if self.command.trim().is_empty() {
            return Err("server.command is required".to_string());
        }
        Ok(())
    }
}

fn default_payload() -> Value {
    Value::Object(Map::new())
}

#[cfg(test)]
mod tests {
    use super::{RequestEnvelope, ServerConfig};

    #[test]
    fn request_payload_defaults_to_empty_object() {
        let decoded: RequestEnvelope =
            serde_json::from_str(r#"{"id":"1","op":"health"}"#).expect("decode");
        assert!(decoded.payload.is_object());
    }

    #[test]
    fn server_validation_requires_identity_and_command() {
        let invalid = ServerConfig::default();
        assert!(invalid.validate().is_err());
    }
}
