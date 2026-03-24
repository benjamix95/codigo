use super::common::{with_json_input, with_raw_json_input, BACKEND_VERSION};
use crate::scoring::{handle_search_request, RustSearchResponsePayload};
use crate::tokenize::handle_tokenize_request;
use std::os::raw::c_char;

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
    with_raw_json_input(input, |raw| {
        match handle_tokenize_request(raw) {
        Ok(response) => response,
        Err(message) => {
            serde_json::to_string(&RustSearchResponsePayload::error("tokenize_failed", &message))
                .unwrap_or_else(|_| "{\"error\":{\"code\":\"tokenize_failed\",\"message\":\"response encoding failed\"},\"hits\":[]}".to_string())
        }
    }
    })
}
