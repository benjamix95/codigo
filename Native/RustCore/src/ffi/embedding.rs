//! FFI entry points for embedding generation.

use super::common::with_raw_json_input;
use crate::embedding::handle_embed_request;
use std::os::raw::c_char;

/// Generate embeddings for one or more texts.
///
/// Input JSON:  `{ "texts": ["hello world", ...], "modelPath": "/path/to/model.onnx" }`
/// Output JSON: `{ "embeddings": [[0.1, ...], ...], "error": null }`
#[no_mangle]
pub extern "C" fn solocode_embed_text(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| handle_embed_request(raw))
}
