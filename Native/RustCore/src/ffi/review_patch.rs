use super::common::{encode_raw, with_raw_json_input};
use crate::review_patch::{
    apply_runtime_result, build_apply_execution_context, build_apply_result, build_merge_execution_context, build_merge_result, build_open_pr_context,
    build_open_pr_execution_context, build_open_pr_result,
    build_prepare_context, build_prepare_result, build_revalidate_execution_context, build_revalidate_result,
    build_resolve_conflicts_context, build_resolve_conflicts_result,
    build_rollback_execution_context, build_rollback_result, build_verify_result, get_runtime_state, handle_patch_action,
    start_runtime,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_patch_handle_action(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchActionRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err(
                        "decode_failed",
                        &err.to_string(),
                    ));
                }
            };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_patch::models::ReviewPatchActionResponse::err(
                "unsupported_schema",
                "schemaVersion must be 1",
            ));
        }
        encode_raw(&handle_patch_action(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_workflow(input: *const c_char) -> *mut c_char {
    review_core_patch_handle_action(input)
}

#[no_mangle]
pub extern "C" fn review_core_patch_start_runtime(input: *const c_char) -> *mut c_char {
    runtime_request_call(input, start_runtime)
}

#[no_mangle]
pub extern "C" fn review_core_patch_apply_runtime_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&apply_runtime_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_get_runtime_state(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeStateRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&get_runtime_state(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_prepare_context(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchPrepareContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchPrepareContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::models::ReviewPatchPrepareContextResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_prepare_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_prepare_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchPrepareResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchPrepareResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_prepare_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_verify_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchVerifyResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchVerifyResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::models::ReviewPatchVerifyResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_verify_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_apply_execution_context(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchApplyExecutionContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchApplyExecutionContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_apply_execution_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_apply_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchApplyResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchApplyResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::models::ReviewPatchApplyResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_apply_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_revalidate_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRevalidateResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchRevalidateResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::models::ReviewPatchRevalidateResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_revalidate_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_revalidate_execution_context(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRevalidateExecutionContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchRevalidateExecutionContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_revalidate_execution_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_rollback_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRollbackResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchRollbackResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::models::ReviewPatchRollbackResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_rollback_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_rollback_execution_context(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRollbackExecutionContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::models::ReviewPatchRollbackExecutionContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_rollback_execution_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_open_pr_context(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchOpenPrContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchOpenPrContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_open_pr_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_open_pr_execution_context(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchOpenPrExecutionContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchOpenPrExecutionContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_open_pr_execution_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_open_pr_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchOpenPrResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchOpenPrResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::pr_result_models::ReviewPatchOpenPrResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_open_pr_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_merge_result(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchMergeResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchMergeResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::pr_result_models::ReviewPatchMergeResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_merge_result(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_merge_execution_context(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchMergeExecutionContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchMergeExecutionContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_merge_execution_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_resolve_conflicts_context(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchResolveConflictsContextRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchResolveConflictsContextResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        encode_raw(&build_resolve_conflicts_context(request))
    })
}

#[no_mangle]
pub extern "C" fn review_core_patch_build_resolve_conflicts_result(
    input: *const c_char,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::pr_result_models::ReviewPatchResolveConflictsResultRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_patch::pr_result_models::ReviewPatchResolveConflictsResultResponse::error(
                            err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_patch::pr_result_models::ReviewPatchResolveConflictsResultResponse::error(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_resolve_conflicts_result(request))
    })
}

fn runtime_request_call(
    input: *const c_char,
    handler: fn(
        crate::review_patch::models::ReviewPatchRuntimeStartRequest,
    ) -> crate::review_patch::models::ReviewPatchRuntimeResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_patch::models::ReviewPatchRuntimeStartRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => return patch_runtime_error("decode_failed", &err.to_string()),
            };
        if request.schema_version != 1 {
            return patch_runtime_error("unsupported_schema", "schemaVersion must be 1");
        }
        encode_raw(&handler(request))
    })
}

fn patch_runtime_error(code: &str, message: &str) -> String {
    encode_raw(&crate::review_patch::models::ReviewPatchRuntimeResponse::err(
        code, message,
    ))
}
