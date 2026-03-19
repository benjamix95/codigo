use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::runtime_callbacks::{
    reduce_prepare_verified_patches_callback, reduce_tests_callback, ReviewRuntimePatchReductionRequest,
    ReviewRuntimeReductionResponse, ReviewRuntimeTestsReductionRequest,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_runtime_reduce_tests(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewRuntimeTestsReductionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewRuntimeReductionResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&reduce_tests_callback(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_runtime_reduce_prepare_verified_patches(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewRuntimePatchReductionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewRuntimeReductionResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&reduce_prepare_verified_patches_callback(request))
    })
}
