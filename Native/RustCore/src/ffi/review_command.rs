use super::common::{encode_raw, with_raw_json_input};
use crate::review_command::{build_start_prompt, finalize_deferred_command, mutate_snapshot, plan_command};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_command_plan(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_command::models::ReviewCommandPlanRequest =
            match serde_json::from_str(raw) {
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
        encode_raw(&plan_command(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_command_mutate_snapshot(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_command::models::ReviewCommandMutationRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_command::models::ReviewCommandMutationResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_command::models::ReviewCommandMutationResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&mutate_snapshot(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_command_finalize_deferred(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_command::models::ReviewDeferredCommandFinalizeRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_command::models::ReviewDeferredCommandFinalizeResponse::success(
                            "failed",
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_command::models::ReviewDeferredCommandFinalizeResponse::success(
                    "failed",
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&finalize_deferred_command(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_command_build_start_prompt(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_command::models::ReviewCommandPromptRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_command::models::ReviewCommandPromptResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_command::models::ReviewCommandPromptResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_start_prompt(request))
    })
}
