use super::common::{encode_raw, with_raw_json_input};
use crate::review_panel::{
    derive_panel_history_live, derive_panel_history_records, extract_panel_chat_findings,
    plan_panel_launch, ReviewPanelChatExtractRequest, ReviewPanelSnapshotRequest,
};
use crate::review_command::models::ReviewCommandPlanRequest;
use crate::review_models::ReviewCoreReduceResponse;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_panel_launch(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewCommandPlanRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &crate::review_command::models::ReviewCommandPlanResponse::error(
                        err.to_string(),
                    ),
                );
            }
        };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_command::models::ReviewCommandPlanResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&plan_panel_launch(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_panel_chat_extract(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewPanelChatExtractRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &crate::review_panel::ReviewPanelChatExtractResponse::error(
                        "decode_failed",
                        &err.to_string(),
                        String::new(),
                        Vec::new(),
                        false,
                    ),
                );
            }
        };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_panel::ReviewPanelChatExtractResponse::error(
                    "unsupported_schema",
                    "schemaVersion must be 1",
                    request.content,
                    request.existing_findings,
                    false,
                ),
            );
        }
        encode_raw(&extract_panel_chat_findings(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_panel_history_live(input: *const c_char) -> *mut c_char {
    snapshot_call(input, |request| {
        ReviewCoreReduceResponse::success_panel_state(derive_panel_history_live(request.snapshot))
    })
}

#[no_mangle]
pub extern "C" fn review_core_panel_history_records(input: *const c_char) -> *mut c_char {
    snapshot_call(input, |request| {
        ReviewCoreReduceResponse::success(derive_panel_history_records(request.snapshot))
    })
}

fn snapshot_call(
    input: *const c_char,
    handler: fn(ReviewPanelSnapshotRequest) -> ReviewCoreReduceResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewPanelSnapshotRequest = match serde_json::from_str(raw) {
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
        encode_raw(&handler(request))
    })
}
