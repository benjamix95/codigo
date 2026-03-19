use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::candidates::{
    candidate_from_finding, candidate_from_task, ReviewCandidateFromFindingRequest,
    ReviewCandidateFromTaskRequest, ReviewCandidateRuntimeResponse,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_candidate_from_finding(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewCandidateFromFindingRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCandidateRuntimeResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&candidate_from_finding(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_candidate_from_review_task(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewCandidateFromTaskRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCandidateRuntimeResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&candidate_from_task(request))
    })
}
