use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::provider::{
    plan_step, reduce_event, ReviewProviderPlanRequest, ReviewProviderReduceRequest,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_provider_plan_step(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewProviderPlanRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &crate::review_pipeline::provider::ReviewProviderPlanResponse::error(
                        "decode_failed",
                        &err.to_string(),
                    ),
                )
            }
        };
        encode_raw(&plan_step(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_provider_reduce_event(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewProviderReduceRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &crate::review_pipeline::provider::ReviewProviderReduceResponse::error(
                        "decode_failed",
                        &err.to_string(),
                    ),
                )
            }
        };
        encode_raw(&reduce_event(request))
    })
}
