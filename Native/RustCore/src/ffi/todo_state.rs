use super::common::{encode_raw, with_raw_json_input};
use crate::todo_state::handle_action;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::os::raw::c_char;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct TodoStateRequest {
    schema_version: i32,
    action: String,
    arguments: BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TodoStateResponse {
    schema_version: i32,
    error: Option<TodoStateError>,
    message: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct TodoStateError {
    code: String,
    message: String,
}

#[no_mangle]
pub extern "C" fn todo_state_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: TodoStateRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&TodoStateResponse::error("decode_failed", &err.to_string()));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&TodoStateResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match handle_action(&request.action, &request.arguments) {
            Ok(message) => encode_raw(&TodoStateResponse::success(message)),
            Err(message) => encode_raw(&TodoStateResponse::error("todo_state_failed", &message)),
        }
    })
}

impl TodoStateResponse {
    fn success(message: String) -> Self {
        Self {
            schema_version: 1,
            error: None,
            message: Some(message),
        }
    }

    fn error(code: &str, message: &str) -> Self {
        Self {
            schema_version: 1,
            error: Some(TodoStateError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            message: None,
        }
    }
}
