use crate::review_audit::run_audit;
use crate::review_history::shape_historical_findings;
use crate::review_models::{
    ReviewAuditRequest, ReviewCoreAuditResponse, ReviewCoreListResponse, ReviewCoreProjectionResponse,
    ReviewCoreReduceResponse, ReviewCoreReplayResponse, ReviewCoreSecurityGateResponse,
    ReviewCoreSyncResponse, ReviewHistoricalShapeRequest, ReviewProjectionRequest, ReviewReplayRequest,
    ReviewSecurityGateRequest, ReviewSyncRequest, ReviewVerifyRequest,
};
use crate::review_projection::build_projection;
use crate::review_replay::build_replay_report;
use crate::review_reduce::merge_history;
use crate::review_security_gate::evaluate_security_gate;
use crate::review_sync::sync_findings;
use crate::review_verify::verify_candidates;
use crate::scoring::{handle_search_request, RustSearchResponsePayload};
use crate::tokenize::handle_tokenize_request;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

const BACKEND_VERSION: &[u8] = b"solocode_rust_core/0.1.0\0";

#[no_mangle]
pub extern "C" fn solocode_search_backend_version() -> *const c_char {
    BACKEND_VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn solocode_semantic_search(input: *const c_char) -> *mut c_char {
    with_json_input(input, |raw| match handle_search_request(raw) {
        Ok(response) => response,
        Err(message) => RustSearchResponsePayload::error("search_failed", &message),
    })
}

#[no_mangle]
pub extern "C" fn solocode_semantic_tokenize(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| match handle_tokenize_request(raw) {
        Ok(response) => response,
        Err(message) => {
            serde_json::to_string(&RustSearchResponsePayload::error("tokenize_failed", &message))
                .unwrap_or_else(|_| "{\"error\":{\"code\":\"tokenize_failed\",\"message\":\"response encoding failed\"},\"hits\":[]}".to_string())
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_version() -> *const c_char {
    BACKEND_VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn review_core_verify_candidates(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewVerifyRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreListResponse::<serde_json::Value>::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreListResponse::<serde_json::Value>::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match verify_candidates(request.candidates, &request.workspace_path, request.scope_files) {
            Ok(results) => encode_raw(&ReviewCoreListResponse::success(results)),
            Err(message) => encode_raw(&ReviewCoreListResponse::<serde_json::Value>::error("verify_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_sync_verified_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSyncRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreSyncResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreSyncResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match sync_findings(request.findings, request.trace_log) {
            Ok((findings, projection)) => encode_raw(&ReviewCoreSyncResponse::success(findings, projection)),
            Err(message) => encode_raw(&ReviewCoreSyncResponse::error("sync_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_run_audit(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewAuditRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreAuditResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreAuditResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match run_audit(&request.tool_name, request.scope_files, &request.workspace_path) {
            Ok(result) => encode_raw(&ReviewCoreAuditResponse::success(result)),
            Err(message) if message == "unsupported_tool" => encode_raw(&ReviewCoreAuditResponse::error("unsupported_tool", "tool not implemented in rust core")),
            Err(message) => encode_raw(&ReviewCoreAuditResponse::error("audit_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_reduce_panel_state(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_models::ReviewReduceRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreReduceResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReduceResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match request.operation.as_str() {
            "merge_history" => encode_raw(&ReviewCoreReduceResponse::success(merge_history(request.primary, request.fallback))),
            _ => encode_raw(&ReviewCoreReduceResponse::error("unsupported_operation", "operation not implemented")),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_build_projection(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewProjectionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreProjectionResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreProjectionResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        encode_raw(&ReviewCoreProjectionResponse::success(build_projection(&request.findings, &request.trace_log)))
    })
}

#[no_mangle]
pub extern "C" fn review_core_replay_verified_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewReplayRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreReplayResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReplayResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match build_replay_report(&request.envelope, &request.checkpoint_source) {
            Ok(report) => encode_raw(&ReviewCoreReplayResponse::success(report)),
            Err(message) => encode_raw(&ReviewCoreReplayResponse::error("replay_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_evaluate_security_gate(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSecurityGateRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreSecurityGateResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreSecurityGateResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        match evaluate_security_gate(&request.envelope) {
            Ok(report) => encode_raw(&ReviewCoreSecurityGateResponse::success(report)),
            Err(message) => encode_raw(&ReviewCoreSecurityGateResponse::error("security_gate_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_shape_historical_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewHistoricalShapeRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreReduceResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReduceResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        encode_raw(&ReviewCoreReduceResponse::success(shape_historical_findings(request.records)))
    })
}

#[no_mangle]
pub extern "C" fn solocode_free_buffer(buffer: *mut c_char) {
    if buffer.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(buffer);
    }
}

fn with_json_input<F>(input: *const c_char, handler: F) -> *mut c_char
where
    F: FnOnce(&str) -> RustSearchResponsePayload,
{
    let payload = if input.is_null() {
        RustSearchResponsePayload::error("invalid_input", "null input buffer")
    } else {
        let raw = unsafe { CStr::from_ptr(input) };
        match raw.to_str() {
            Ok(text) => handler(text),
            Err(_) => RustSearchResponsePayload::error("invalid_utf8", "input was not valid UTF-8"),
        }
    };

    let encoded = serde_json::to_string(&payload)
        .unwrap_or_else(|_| "{\"error\":{\"code\":\"encode_failed\",\"message\":\"response encoding failed\"},\"hits\":[]}".to_string());

    CString::new(encoded)
        .unwrap_or_else(|_| CString::new("{\"error\":{\"code\":\"cstring_failed\",\"message\":\"response contained interior nul\"},\"hits\":[]}").unwrap())
        .into_raw()
}

fn with_raw_json_input<F>(input: *const c_char, handler: F) -> *mut c_char
where
    F: FnOnce(&str) -> String,
{
    let payload = if input.is_null() {
        "{\"error\":{\"code\":\"invalid_input\",\"message\":\"null input buffer\"}}".to_string()
    } else {
        let raw = unsafe { CStr::from_ptr(input) };
        match raw.to_str() {
            Ok(text) => handler(text),
            Err(_) => "{\"error\":{\"code\":\"invalid_utf8\",\"message\":\"input was not valid UTF-8\"}}".to_string(),
        }
    };

    CString::new(payload)
        .unwrap_or_else(|_| CString::new("{\"error\":{\"code\":\"cstring_failed\",\"message\":\"response contained interior nul\"}}").unwrap())
        .into_raw()
}

fn encode_raw<T: serde::Serialize>(payload: &T) -> String {
    serde_json::to_string(payload).unwrap_or_else(|_| {
        "{\"schemaVersion\":1,\"error\":{\"code\":\"encode_failed\",\"message\":\"response encoding failed\"}}".to_string()
    })
}
