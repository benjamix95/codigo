use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
#[serde(untagged)]
pub enum JsonRpcId {
    Number(i64),
    String(String),
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub id: JsonRpcId,
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct JsonRpcNotification {
    pub jsonrpc: String,
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(untagged)]
pub enum JsonRpcInbound {
    Request(JsonRpcRequest),
    Notification(JsonRpcNotification),
}

#[derive(Clone, Debug, Serialize)]
pub struct JsonRpcResponse<T: Serialize> {
    pub jsonrpc: &'static str,
    pub id: JsonRpcId,
    pub result: T,
}

#[derive(Clone, Debug, Serialize)]
pub struct JsonRpcErrorResponse {
    pub jsonrpc: &'static str,
    pub id: JsonRpcId,
    pub error: JsonRpcError,
}

#[derive(Clone, Debug, Serialize)]
pub struct JsonRpcError {
    pub code: i64,
    pub message: String,
}

impl<T: Serialize> JsonRpcResponse<T> {
    pub fn ok(id: JsonRpcId, result: T) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result,
        }
    }
}

impl JsonRpcErrorResponse {
    pub fn parse_error(id: JsonRpcId, message: impl Into<String>) -> Self {
        Self::new(id, -32700, message)
    }

    pub fn invalid_request(id: JsonRpcId, message: impl Into<String>) -> Self {
        Self::new(id, -32600, message)
    }

    pub fn method_not_found(id: JsonRpcId, message: impl Into<String>) -> Self {
        Self::new(id, -32601, message)
    }

    pub fn invalid_params(id: JsonRpcId, message: impl Into<String>) -> Self {
        Self::new(id, -32602, message)
    }

    fn new(id: JsonRpcId, code: i64, message: impl Into<String>) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            error: JsonRpcError {
                code,
                message: message.into(),
            },
        }
    }
}
