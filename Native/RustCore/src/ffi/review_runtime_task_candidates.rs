use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::runtime_task_candidates::{
    reduce_prepare_task_candidates, ReviewRuntimeTaskCandidatesRequest,
    ReviewRuntimeTaskCandidatesResponse,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_runtime_reduce_prepare_task_candidates(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewRuntimeTaskCandidatesRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewRuntimeTaskCandidatesResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&reduce_prepare_task_candidates(request))
    })
}
