use super::common::{encode_raw, with_raw_json_input};
use crate::review_pipeline::{
    apply_callback_result, cancel_session, get_snapshot, resume_session, start_session,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_run_pipeline(input: *const c_char) -> *mut c_char {
    review_core_pipeline_start_session(input)
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_start_session(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineStartRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
            };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&start_session(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_apply_callback_result(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineApplyRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
            };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&apply_callback_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_get_snapshot(input: *const c_char) -> *mut c_char {
    session_request_call(input, get_snapshot)
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_resume(input: *const c_char) -> *mut c_char {
    session_request_call(input, resume_session)
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_cancel(input: *const c_char) -> *mut c_char {
    session_request_call(input, cancel_session)
}

fn session_request_call(
    input: *const c_char,
    handler: fn(
        crate::review_pipeline::requests::ReviewPipelineSessionRequest,
    ) -> crate::review_pipeline::models::ReviewPipelineResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineSessionRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
            };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&handler(request))
    })
}

fn pipeline_decode_error(
    session_id: &str,
    message: &str,
) -> crate::review_pipeline::models::ReviewPipelineResponse {
    crate::review_pipeline::models::ReviewPipelineResponse::error(
        session_id.to_string(),
        pipeline_placeholder_snapshot(session_id),
        "decode_failed",
        message,
    )
}

fn pipeline_schema_error(session_id: &str) -> crate::review_pipeline::models::ReviewPipelineResponse {
    crate::review_pipeline::models::ReviewPipelineResponse::error(
        session_id.to_string(),
        pipeline_placeholder_snapshot(session_id),
        "unsupported_schema",
        "schemaVersion must be 1",
    )
}

fn pipeline_placeholder_snapshot(
    session_id: &str,
) -> crate::review_pipeline::models::ReviewPipelineSnapshot {
    crate::review_pipeline::state::PipelineSession::new(
        session_id.to_string(),
        None,
        String::new(),
        crate::review_pipeline::models::ReviewPipelineConfig {
            max_workers: 1,
            max_review_rounds: 1,
            enabled_phases: "analysis-and-execution".to_string(),
            analysis_backend: "codex".to_string(),
            execution_backend: "codex".to_string(),
        },
        String::new(),
        None,
        "uncommitted".to_string(),
    )
    .snapshot
}
