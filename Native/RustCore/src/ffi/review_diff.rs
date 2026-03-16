use super::common::{encode_raw, with_raw_json_input};
use crate::review_diff::{render_summary, ReviewDiffSummaryRequest, ReviewDiffSummaryResponse};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_render_diff_summary(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewDiffSummaryRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&ReviewDiffSummaryResponse::error(
                    "decode_failed",
                    &err.to_string(),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&ReviewDiffSummaryResponse::error(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        match render_summary(request) {
            Ok(summary) => encode_raw(&ReviewDiffSummaryResponse::success(summary)),
            Err(message) => encode_raw(&ReviewDiffSummaryResponse::error("diff_failed", &message)),
        }
    })
}
