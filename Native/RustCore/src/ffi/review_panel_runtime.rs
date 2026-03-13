use super::common::{encode_raw, with_raw_json_input};
use crate::review_panel_runtime::{
    finish_chat_runtime, finish_run_runtime, reduce_output_event, start_chat_runtime,
    start_run_runtime, ReviewPanelChatFinishRequest, ReviewPanelChatStartRequest,
    ReviewPanelEventReduceRequest, ReviewPanelRunFinishRequest, ReviewPanelRunStartRequest,
    ReviewPanelRuntimeResponse,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_panel_run_start(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelRunStartRequest| start_run_runtime(request))
}

#[no_mangle]
pub extern "C" fn review_core_panel_run_reduce_event(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelEventReduceRequest| {
        ReviewPanelRuntimeResponse::success(reduce_output_event(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_panel_run_finish(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelRunFinishRequest| finish_run_runtime(request))
}

#[no_mangle]
pub extern "C" fn review_core_panel_chat_start(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelChatStartRequest| start_chat_runtime(request))
}

#[no_mangle]
pub extern "C" fn review_core_panel_chat_reduce_event(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelEventReduceRequest| {
        ReviewPanelRuntimeResponse::success(reduce_output_event(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_panel_chat_finish(input: *const c_char) -> *mut c_char {
    decode_call(input, |request: ReviewPanelChatFinishRequest| finish_chat_runtime(request))
}

fn decode_call<Request: serde::de::DeserializeOwned>(
    input: *const c_char,
    handler: fn(Request) -> ReviewPanelRuntimeResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: Request = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewPanelRuntimeResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        encode_raw(&handler(request))
    })
}
