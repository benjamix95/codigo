use super::common::{encode_raw, with_raw_json_input};
use crate::main_chat::{handle_ui_intent, project_ui};
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiIntentResponse, MainChatUiProjectRequest,
    MainChatUiProjectResponse,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn chat_core_ui_project(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_ui_project_call(raw, project_ui))
}

#[no_mangle]
pub extern "C" fn chat_core_ui_handle_intent(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_ui_intent_call(raw, handle_ui_intent))
}

fn decode_ui_project_call(
    raw: &str,
    handler: impl FnOnce(MainChatUiProjectRequest) -> MainChatUiProjectResponse,
) -> String {
    let request: MainChatUiProjectRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatUiProjectResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_ui_intent_call(
    raw: &str,
    handler: impl FnOnce(MainChatUiIntentRequest) -> MainChatUiIntentResponse,
) -> String {
    let request: MainChatUiIntentRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatUiIntentResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}
