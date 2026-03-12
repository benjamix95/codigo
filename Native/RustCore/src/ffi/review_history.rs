use super::common::{encode_raw, with_raw_json_input, ReviewFindDuplicateRequest};
use crate::review_history::shape_historical_findings;
use crate::review_identity::find_duplicate;
use crate::review_models::{ReviewCoreAuditResponse, ReviewCoreReduceResponse, ReviewHistoricalShapeRequest};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_shape_historical_findings(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewHistoricalShapeRequest = match serde_json::from_str(raw) {
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
        encode_raw(&ReviewCoreReduceResponse::success(shape_historical_findings(
            request.records,
        )))
    })
}

#[no_mangle]
pub extern "C" fn review_core_find_duplicate(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewFindDuplicateRequest = match serde_json::from_str(raw) {
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
