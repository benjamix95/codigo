use crate::review_audit::run_audit;
use crate::review_history::shape_historical_findings;
use crate::review_identity::find_duplicate;
use crate::review_mcp::{
    build_review_index, claim_commands, enqueue_bughunter_command, enqueue_review_command,
    handle_bughunter_tool, handle_review_tool, handle_security_tool, heartbeat_command,
    mark_command,
};
use crate::review_patch::handle_patch_action;
use crate::review_pipeline::{
    apply_callback_result, cancel_session, get_snapshot, resume_session, start_session,
};
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

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReviewFindDuplicateRequest {
    schema_version: i32,
    candidate: serde_json::Value,
    existing: Vec<serde_json::Value>,
    minimum_score: Option<f64>,
}

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
pub extern "C" fn review_core_find_duplicate(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewFindDuplicateRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&ReviewCoreAuditResponse::error("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreAuditResponse::error("unsupported_schema", "schemaVersion must be 1"));
        }
        let result = find_duplicate(
            &request.candidate,
            &request.existing,
            request.minimum_score.unwrap_or(0.75),
        );
        encode_raw(&ReviewCoreAuditResponse {
            schema_version: 1,
            error: None,
            result,
        })
    })
}

#[no_mangle]
pub extern "C" fn review_core_run_pipeline(input: *const c_char) -> *mut c_char {
    review_core_pipeline_start_session(input)
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_start_session(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineStartRequest = match serde_json::from_str(raw) {
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
pub extern "C" fn review_core_pipeline_apply_callback_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineApplyRequest = match serde_json::from_str(raw) {
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
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineSessionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&get_snapshot(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_resume(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineSessionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&resume_session(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_pipeline_cancel(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_pipeline::requests::ReviewPipelineSessionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&pipeline_decode_error("unknown", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&pipeline_schema_error(&request.session_id));
        }
        encode_raw(&cancel_session(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_handle_tool(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPToolRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err(format!("decode_failed: {}", err))),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err("unsupported_schema"));
        }
        encode_raw(&handle_review_tool(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_security_handle_tool(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPToolRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err(format!("decode_failed: {}", err))),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err("unsupported_schema"));
        }
        encode_raw(&handle_security_tool(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_bughunter_handle_tool(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPToolRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err(format!("decode_failed: {}", err))),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err("unsupported_schema"));
        }
        encode_raw(&handle_bughunter_tool(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_enqueue_command(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPCommandQueueRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(format!("decode_failed: {}", err), Vec::new())),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err("unsupported_schema", request.commands));
        }
        let response = match request.queue_kind.as_str() {
            "review" => enqueue_review_command(request),
            "bughunter" => enqueue_bughunter_command(request),
            _ => crate::review_mcp::models::ReviewMCPCommandQueueResponse::err("unsupported_queue_kind", request.commands),
        };
        encode_raw(&response)
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_claim_commands(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPCommandQueueRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(format!("decode_failed: {}", err), Vec::new())),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err("unsupported_schema", request.commands));
        }
        encode_raw(&claim_commands(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_mark_command(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPCommandQueueRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(format!("decode_failed: {}", err), Vec::new())),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err("unsupported_schema", request.commands));
        }
        encode_raw(&mark_command(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_command_heartbeat(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPCommandQueueRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(format!("decode_failed: {}", err), Vec::new())),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPCommandQueueResponse::err("unsupported_schema", request.commands));
        }
        encode_raw(&heartbeat_command(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_read_index(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPIndexRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(_) => return "{\"schemaVersion\":1,\"latestSessionId\":null,\"latestSessionIdByConversation\":{},\"sessions\":[]}".to_string(),
        };
        if request.schema_version != 1 {
            return "{\"schemaVersion\":1,\"latestSessionId\":null,\"latestSessionIdByConversation\":{},\"sessions\":[]}".to_string();
        }
        encode_raw(&build_review_index(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchActionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err("decode_failed", &err.to_string())),
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err("unsupported_schema", "schemaVersion must be 1"));
        }
        encode_raw(&handle_patch_action(request))
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

fn pipeline_decode_error(session_id: &str, message: &str) -> crate::review_pipeline::models::ReviewPipelineResponse {
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

fn pipeline_placeholder_snapshot(session_id: &str) -> crate::review_pipeline::models::ReviewPipelineSnapshot {
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
