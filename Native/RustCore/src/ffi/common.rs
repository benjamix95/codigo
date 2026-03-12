use crate::scoring::RustSearchResponsePayload;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub(crate) const BACKEND_VERSION: &[u8] = b"solocode_rust_core/0.1.0\0";

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ReviewFindDuplicateRequest {
    pub(crate) schema_version: i32,
    pub(crate) candidate: serde_json::Value,
    pub(crate) existing: Vec<serde_json::Value>,
    pub(crate) minimum_score: Option<f64>,
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

pub(crate) fn with_json_input<F>(input: *const c_char, handler: F) -> *mut c_char
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

pub(crate) fn with_raw_json_input<F>(input: *const c_char, handler: F) -> *mut c_char
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

pub(crate) fn encode_raw<T: serde::Serialize>(payload: &T) -> String {
    serde_json::to_string(payload).unwrap_or_else(|_| {
        "{\"schemaVersion\":1,\"error\":{\"code\":\"encode_failed\",\"message\":\"response encoding failed\"}}".to_string()
    })
}
