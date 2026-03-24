use super::common::{encode_raw, with_raw_json_input};
use crate::review_persistence::{
    build_review_index_response, decode_bughunter_commands_response,
    decode_bughunter_snapshot_response, decode_review_commands_response,
    decode_review_snapshot_response, encode_bughunter_commands_response,
    encode_bughunter_snapshot_response, encode_review_commands_response,
    encode_review_snapshot_response,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_persistence_encode_review_snapshot(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, encode_review_snapshot_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_decode_review_snapshot(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, decode_review_snapshot_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_encode_bughunter_snapshot(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, encode_bughunter_snapshot_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_decode_bughunter_snapshot(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, decode_bughunter_snapshot_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_encode_review_commands(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, encode_review_commands_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_decode_review_commands(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, decode_review_commands_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_encode_bughunter_commands(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, encode_bughunter_commands_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_decode_bughunter_commands(
    input: *const c_char,
) -> *mut c_char {
    persistence_payload_call(input, decode_bughunter_commands_response)
}

#[no_mangle]
pub extern "C" fn review_core_persistence_build_review_index(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_persistence::models::ReviewPersistenceIndexRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_persistence::models::ReviewPersistencePayloadResponse::err(
                            &err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_persistence::models::ReviewPersistencePayloadResponse::err(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&build_review_index_response(request))
    })
}

fn persistence_payload_call(
    input: *const c_char,
    handler: fn(
        crate::review_persistence::models::ReviewPersistencePayloadRequest,
    ) -> crate::review_persistence::models::ReviewPersistencePayloadResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_persistence::models::ReviewPersistencePayloadRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_persistence::models::ReviewPersistencePayloadResponse::err(
                            &err.to_string(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_persistence::models::ReviewPersistencePayloadResponse::err(
                    "schemaVersion must be 1",
                ),
            );
        }
        encode_raw(&handler(request))
    })
}
