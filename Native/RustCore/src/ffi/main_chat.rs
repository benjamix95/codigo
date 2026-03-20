use super::common::{encode_raw, with_raw_json_input};
use crate::main_chat::{
    apply_event, bridge_provider_stream, cancel_session, finish_turn, get_snapshot, handle_action,
    handle_markers_request, handle_reasoning_request, handle_runtime_action, handle_store_action,
    handle_task_runtime_action, load_store_snapshot, replace_store_snapshot,
    resolve_thread_provider_selection, resume_session, start_session, start_turn,
};
use app_core_protocol::main_chat_markers::{MainChatMarkersRequest, MainChatMarkersResponse};
use app_core_protocol::main_chat::{
    MainChatActionRequest, MainChatReduceEventRequest, MainChatRuntimeResponse,
};
use app_core_protocol::main_chat_reasoning::{
    MainChatReasoningRequest, MainChatReasoningResponse,
};
use app_core_protocol::main_chat_provider::{
    MainChatProviderSessionResponse,
};
use app_core_protocol::main_chat_store::{
    MainChatStoreActionRequest, MainChatStoreResponse, MainChatStoreSnapshot,
};
use app_core_protocol::main_chat_task_runtime::{
    MainChatTaskRuntimeRequest, MainChatTaskRuntimeResponse,
};
use app_core_protocol::main_chat_runtime::MainChatRuntimeActionRequest;
use app_core_protocol::thread_provider_selection::{
    ThreadProviderSelectionRequest, ThreadProviderSelectionResponse,
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

#[no_mangle]
pub extern "C" fn chat_core_provider_start_session(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_provider_call(raw, start_session))
}

#[no_mangle]
pub extern "C" fn chat_core_provider_resume(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_provider_call(raw, resume_session))
}

#[no_mangle]
pub extern "C" fn chat_core_provider_get_snapshot(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_provider_call(raw, get_snapshot))
}

#[no_mangle]
pub extern "C" fn chat_core_provider_cancel(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_provider_call(raw, cancel_session))
}

#[no_mangle]
pub extern "C" fn chat_core_reasoning_handle(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_reasoning_call(raw, handle_reasoning_request))
}

#[no_mangle]
pub extern "C" fn chat_core_markers_handle(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_markers_call(raw, handle_markers_request))
}

#[no_mangle]
pub extern "C" fn chat_core_task_runtime_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_task_runtime_call(raw, handle_task_runtime_action))
}

#[no_mangle]
pub extern "C" fn chat_core_thread_provider_selection(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        decode_thread_provider_selection_call(raw, resolve_thread_provider_selection)
    })
}

#[no_mangle]
pub extern "C" fn chat_core_store_load(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_store_snapshot_call(raw, load_store_snapshot))
}

#[no_mangle]
pub extern "C" fn chat_core_store_replace_snapshot(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_store_snapshot_call(raw, replace_store_snapshot))
}

#[no_mangle]
pub extern "C" fn chat_core_store_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| decode_store_action_call(raw, handle_store_action))
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

fn decode_provider_call<Req>(
    raw: &str,
    handler: impl FnOnce(Req) -> MainChatProviderSessionResponse,
) -> String
where
    Req: serde::de::DeserializeOwned,
{
    let request: Req = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatProviderSessionResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_store_snapshot_call(
    raw: &str,
    handler: impl FnOnce(MainChatStoreSnapshot) -> MainChatStoreResponse,
) -> String {
    let request: MainChatStoreSnapshot = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatStoreResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_store_action_call(
    raw: &str,
    handler: impl FnOnce(MainChatStoreActionRequest) -> MainChatStoreResponse,
) -> String {
    let request: MainChatStoreActionRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatStoreResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_thread_provider_selection_call(
    raw: &str,
    handler: impl FnOnce(ThreadProviderSelectionRequest) -> ThreadProviderSelectionResponse,
) -> String {
    let request: ThreadProviderSelectionRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&ThreadProviderSelectionResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_reasoning_call(
    raw: &str,
    handler: impl FnOnce(MainChatReasoningRequest) -> MainChatReasoningResponse,
) -> String {
    let request: MainChatReasoningRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatReasoningResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_task_runtime_call(
    raw: &str,
    handler: impl FnOnce(MainChatTaskRuntimeRequest) -> MainChatTaskRuntimeResponse,
) -> String {
    let request: MainChatTaskRuntimeRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatTaskRuntimeResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}

fn decode_markers_call(
    raw: &str,
    handler: impl FnOnce(MainChatMarkersRequest) -> MainChatMarkersResponse,
) -> String {
    let request: MainChatMarkersRequest = match serde_json::from_str(raw) {
        Ok(request) => request,
        Err(err) => {
            return encode_raw(&MainChatMarkersResponse::error(
                "decode_failed",
                &err.to_string(),
            ));
        }
    };
    encode_raw(&handler(request))
}
