use super::common::{encode_raw, with_raw_json_input};
use crate::review_patch::{apply_runtime_result, get_runtime_state, handle_patch_action, start_runtime};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_patch_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchActionRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err(
                        "decode_failed",
                        &err.to_string(),
                    ));
                }
            };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        encode_raw(&handle_patch_action(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_start_runtime(input: *const c_char) -> *mut c_char {
    runtime_request_call(input, start_runtime)
}

#[no_mangle]
pub extern "C" fn review_core_patch_apply_runtime_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&apply_runtime_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_get_runtime_state(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeStateRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&get_runtime_state(request))
    })
}

fn runtime_request_call(
    input: *const c_char,
    handler: fn(
        crate::review_patch::models::ReviewPatchRuntimeStartRequest,
    ) -> crate::review_patch::models::ReviewPatchRuntimeResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeStartRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&handler(request))
    })
}

fn patch_runtime_error(code: &str, message: &str) -> String {
    encode_raw(&crate::review_patch::models::ReviewPatchRuntimeResponse::err(
        code, message,
    ))
}
