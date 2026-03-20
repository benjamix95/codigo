use super::common::{encode_raw, with_raw_json_input};
use crate::main_chat::{
    apply_event, bridge_provider_stream, finish_turn, handle_action, handle_runtime_action,
    start_turn,
};
use app_core_protocol::main_chat::{
    MainChatProviderStreamRequest, MainChatReduceEventRequest, MainChatRuntimeResponse,
    MainChatActionRequest, MainChatFinishRequest, MainChatStartRequest,
};
use app_core_protocol::main_chat_runtime::{
    MainChatRuntimeActionRequest,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn chat_core_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        if let Ok(request) = serde_json::from_str::<MainChatRuntimeActionRequest>(raw) {
            return encode_raw(&handle_runtime_action(request));
        }
        decode_and_encode::<MainChatActionRequest, MainChatRuntimeResponse>(raw, handle_action)
    })
}

#[no_mangle]
pub extern "C" fn chat_core_runtime_start(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_and_encode(raw, start_turn))
}

#[no_mangle]
pub extern "C" fn chat_core_runtime_reduce_event(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: MainChatReduceEventRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&MainChatRuntimeResponse::error("decode_failed", &err.to_string()));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&MainChatRuntimeResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        encode_raw(&MainChatRuntimeResponse::success(apply_event(request.state, &request.event)))
    })
}

#[no_mangle]
pub extern "C" fn chat_core_runtime_finish(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_and_encode(raw, finish_turn))
}

#[no_mangle]
pub extern "C" fn chat_core_provider_stream(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_and_encode(raw, bridge_provider_stream))
}

fn decode_and_encode<Request, Response>(
    raw: &str,
    handler: impl FnOnce(Request) -> Response,
) -> String
where
    Request: serde::de::DeserializeOwned,
    Response: serde::Serialize,
{
    let request: Request = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatRuntimeResponse::error("decode_failed", &err.to_string()));
        }
    };
    encode_raw(&handler(request))
}
