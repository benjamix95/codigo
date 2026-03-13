use super::common::{encode_raw, with_raw_json_input};
use crate::plan_state::handle_action;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::os::raw::c_char;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PlanStateRequest {
    schema_version: i32,
    action: String,
    arguments: BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PlanStateResponse {
    schema_version: i32,
    error: Option<PlanStateError>,
    message: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PlanStateError {
    code: String,
    message: String,
}

#[no_mangle]
pub extern "C" fn plan_state_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: PlanStateRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&PlanStateResponse::error("decode_failed", &err.to_string()));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&PlanStateResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match handle_action(&request.action, &request.arguments) {
            Ok(message) => encode_raw(&PlanStateResponse::success(message)),
            Err(message) => encode_raw(&PlanStateResponse::error("plan_state_failed", &message)),
        }
    })
}

impl PlanStateResponse {
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
            error: Some(PlanStateError {
                code: code.to_string(),
                message: message.to_string(),
            }),
            message: None,
        }
    }
}
