use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::fix_stage::{
    bridge_fix_stage_event, plan_fix_stage, ReviewFixStageEventRequest, ReviewFixStagePlanRequest,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_fix_stage_plan(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewFixStagePlanRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&crate::review_pipeline::fix_stage::ReviewFixStagePlanResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&plan_fix_stage(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_fix_stage_bridge_event(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewFixStageEventRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&crate::review_pipeline::fix_stage::ReviewFixStageEventResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ))
            }
        };
        encode_raw(&bridge_fix_stage_event(request))
    })
}
