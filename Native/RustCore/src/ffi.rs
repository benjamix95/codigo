use crate::scoring::{handle_search_request, RustSearchResponsePayload};
use crate::tokenize::handle_tokenize_request;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

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
