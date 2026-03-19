use super::common::{encode_raw, with_raw_json_input};
use crate::review_session::{
    apply_action, apply_registry_action, derive_view, new_snapshot, ReviewRegistryActionRequest,
    ReviewSessionActionRequest, ReviewSessionProjectionResponse, ReviewSessionResponse,
    ReviewSessionSnapshotNewRequest,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_session_snapshot_new(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSessionSnapshotNewRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewSessionResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewSessionResponse::error("invalid_schema", "schemaVersion must be 1"));
        }
        encode_raw(&new_snapshot(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_session_apply_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSessionActionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewSessionResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewSessionResponse::error("invalid_schema", "schemaVersion must be 1"));
        }
        encode_raw(&apply_action(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_session_derive_view(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSessionActionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewSessionProjectionResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewSessionProjectionResponse::error("invalid_schema", "schemaVersion must be 1"));
        }
        encode_raw(&derive_view(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_registry_apply_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewRegistryActionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewSessionResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewSessionResponse::error("invalid_schema", "schemaVersion must be 1"));
        }
        encode_raw(&apply_registry_action(request))
    })
}
