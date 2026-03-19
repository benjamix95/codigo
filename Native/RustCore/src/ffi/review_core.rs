use super::common::{encode_raw, with_raw_json_input, BACKEND_VERSION};
use crate::review_audit::run_audit;
use crate::review_chat::merge_chat_findings;
use crate::review_finalize::{select_auto_prepare_targets, select_patch_finalization_targets};
use crate::review_history::{
    derive_historical_findings_from_snapshot, derive_history_live_state,
};
use crate::review_models::{
    ReviewAuditRequest, ReviewCoreAuditResponse, ReviewCoreListResponse,
    ReviewFinalizeTargetsRequest,
    ReviewCoreProjectionResponse, ReviewCoreReduceResponse, ReviewCoreReplayResponse,
    ReviewCoreSecurityGateResponse, ReviewCoreSyncResponse, ReviewProjectionRequest,
    ReviewReplayRequest, ReviewSecurityGateRequest, ReviewSyncRequest, ReviewVerifyRequest,
};
use crate::review_projection::build_projection;
use crate::review_reduce::{derive_review_panel_state, merge_history};
use crate::review_replay::build_replay_report;
use crate::review_security_gate::evaluate_security_gate;
use crate::review_sync::sync_findings;
use crate::review_verify::verify_candidates;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_version() -> *const c_char {
    BACKEND_VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn review_core_select_auto_prepare_targets(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewFinalizeTargetsRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreReduceResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReduceResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        encode_raw(&ReviewCoreReduceResponse::success_panel_state(
            select_auto_prepare_targets(&request.snapshot, request.origin_filter.as_deref()),
        ))
    })
}

#[no_mangle]
pub extern "C" fn review_core_verify_candidates(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewVerifyRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &ReviewCoreListResponse::<serde_json::Value>::error(
                        "decode_failed",
                        &err.to_string(),
                    ),
                );
            }
        };
        if request.schema_version != 1 {
            return encode_raw(
                &ReviewCoreListResponse::<serde_json::Value>::error(
                    "unsupported_schema",
                    "schemaVersion must be 1",
                ),
            );
        }
        match verify_candidates(request.candidates, &request.workspace_path, request.scope_files) {
            Ok(results) => encode_raw(&ReviewCoreListResponse::success(results)),
            Err(message) => encode_raw(
                &ReviewCoreListResponse::<serde_json::Value>::error("verify_failed", &message),
            ),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_sync_verified_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewSyncRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreSyncResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreSyncResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match sync_findings(request.findings, request.trace_log) {
            Ok((findings, projection)) => {
                encode_raw(&ReviewCoreSyncResponse::success(findings, projection))
            }
            Err(message) => encode_raw(&ReviewCoreSyncResponse::error("sync_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_run_audit(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewAuditRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreAuditResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreAuditResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match run_audit(&request.tool_name, request.scope_files, &request.workspace_path) {
            Ok(result) => encode_raw(&ReviewCoreAuditResponse::success(result)),
            Err(message) if message == "unsupported_tool" => encode_raw(
                &ReviewCoreAuditResponse::error(
                    "unsupported_tool",
                    "tool not implemented in rust core",
                ),
            ),
            Err(message) => encode_raw(&ReviewCoreAuditResponse::error("audit_failed", &message)),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_reduce_panel_state(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_models::ReviewReduceRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreReduceResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReduceResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match request.operation.as_str() {
            "merge_history" => encode_raw(&ReviewCoreReduceResponse::success(merge_history(
                request.primary.unwrap_or_default(),
                request.fallback.unwrap_or_default(),
            ))),
            "merge_chat_findings" => encode_raw(&ReviewCoreReduceResponse::success_panel_state(
                merge_chat_findings(
                    request.primary.as_deref().unwrap_or(&[]),
                    request.fallback.as_deref().unwrap_or(&[]),
                ),
            )),
            "derive_patch_finalization_targets" => {
                let Some(snapshot) = request.snapshot else {
                    return encode_raw(&ReviewCoreReduceResponse::error(
                        "missing_snapshot",
                        "snapshot is required",
                    ));
                };
                encode_raw(&ReviewCoreReduceResponse::success_panel_state(
                    select_patch_finalization_targets(&snapshot),
                ))
            }
            "derive_history_records_from_snapshot" => {
                let Some(snapshot) = request.snapshot else {
                    return encode_raw(&ReviewCoreReduceResponse::error(
                        "missing_snapshot",
                        "snapshot is required",
                    ));
                };
                encode_raw(&ReviewCoreReduceResponse::success(
                    derive_historical_findings_from_snapshot(&snapshot),
                ))
            }
            "derive_history_live_state" => {
                let Some(snapshot) = request.snapshot else {
                    return encode_raw(&ReviewCoreReduceResponse::error(
                        "missing_snapshot",
                        "snapshot is required",
                    ));
                };
                encode_raw(&ReviewCoreReduceResponse::success_panel_state(
                    derive_history_live_state(&snapshot, &[], &[]),
                ))
            }
            "derive_review_panel_state" => {
                let Some(snapshot) = request.snapshot else {
                    return encode_raw(&ReviewCoreReduceResponse::error(
                        "missing_snapshot",
                        "snapshot is required",
                    ));
                };
                encode_raw(&ReviewCoreReduceResponse::success_panel_state(
                    derive_review_panel_state(snapshot),
                ))
            }
            _ => encode_raw(&ReviewCoreReduceResponse::error(
                "unsupported_operation",
                "operation not implemented",
            )),
        }
    })
}

#[no_mangle]
pub extern "C" fn review_core_build_projection(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewProjectionRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreProjectionResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreProjectionResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        encode_raw(&ReviewCoreProjectionResponse::success(build_projection(
            &request.findings,
            &request.trace_log,
        )))
    })
}

#[no_mangle]
pub extern "C" fn review_core_replay_verified_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewReplayRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewCoreReplayResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreReplayResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
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
            Err(err) => {
                return encode_raw(&ReviewCoreSecurityGateResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewCoreSecurityGateResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match evaluate_security_gate(&request.envelope) {
            Ok(report) => encode_raw(&ReviewCoreSecurityGateResponse::success(report)),
            Err(message) => encode_raw(
                &ReviewCoreSecurityGateResponse::error("security_gate_failed", &message),
            ),
        }
    })
}
