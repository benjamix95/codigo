use super::common::{encode_raw, with_raw_json_input};
use crate::review_git_context::{load_git_context, ReviewPanelGitContextRequest};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_panel_git_context(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: ReviewPanelGitContextRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(
                    &crate::review_git_context::ReviewPanelGitContextResponse::error(
                        "decode_failed",
                        &err.to_string(),
                    ),
                )
            }
        };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_git_context::ReviewPanelGitContextResponse::error(
                    "unsupported_schema",
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&load_git_context(request))
    })
}
