use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::runtime_audit_stage::{
    reduce_audit_stage, ReviewRuntimeAuditStageRequest, ReviewRuntimeAuditStageResponse,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_runtime_reduce_audit_stage(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewRuntimeAuditStageRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewRuntimeAuditStageResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&reduce_audit_stage(request))
    })
}
