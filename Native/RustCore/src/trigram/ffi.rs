//! FFI entry points for the trigram index.

use crate::ffi::common::with_raw_json_input;
use super::index::TrigramIndex;
use super::search;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::os::raw::c_char;
use std::sync::Mutex;

/// Global trigram index (per workspace).
static INDEX: Mutex<Option<TrigramIndex>> = Mutex::new(None);

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuildRequest {
    files: Vec<BuildFileEntry>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuildFileEntry {
    path: String,
    content: String,
    content_hash: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct BuildResponse {
    file_count: usize,
    trigram_count: usize,
    elapsed_ms: u64,
}

fn handle_build(json: &str) -> String {
    let req: BuildRequest = match serde_json::from_str(json) {
        Ok(r) => r,
        Err(e) => return format!(r#"{{"error":"{}"}}"#, e),
    };

    let start = std::time::Instant::now();
    let files: Vec<(String, String, u64)> = req
        .files
        .into_iter()
        .map(|f| (f.path, f.content, f.content_hash))
        .collect();

    let index = TrigramIndex::build(&files);
    let resp = BuildResponse {
        file_count: index.file_count(),
        trigram_count: index.trigram_count(),
        elapsed_ms: start.elapsed().as_millis() as u64,
    };

    if let Ok(mut guard) = INDEX.lock() {
        *guard = Some(index);
    }

    serde_json::to_string(&resp).unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SearchRequest {
    pattern: String,
    max_results: Option<usize>,
    case_sensitive: Option<bool>,
    /// file_id → content (loaded by Swift, passed here to avoid FS access).
    file_contents: Option<HashMap<u32, String>>,
}

fn handle_search(json: &str) -> String {
    let req: SearchRequest = match serde_json::from_str(json) {
        Ok(r) => r,
        Err(e) => return format!(r#"{{"error":"{}"}}"#, e),
    };

    let guard = match INDEX.lock() {
        Ok(g) => g,
        Err(_) => return r#"{"error":"index lock poisoned"}"#.to_string(),
    };

    let index = match guard.as_ref() {
        Some(i) => i,
        None => return r#"{"error":"index not built"}"#.to_string(),
    };

    let contents = req.file_contents.unwrap_or_default();
    let result = search::grep(
        index,
        &req.pattern,
        &contents,
        req.max_results.unwrap_or(200),
        req.case_sensitive.unwrap_or(false),
    );

    serde_json::to_string(&result).unwrap_or_default()
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateRequest {
    files: Vec<BuildFileEntry>,
}

fn handle_update(json: &str) -> String {
    let req: UpdateRequest = match serde_json::from_str(json) {
        Ok(r) => r,
        Err(e) => return format!(r#"{{"error":"{}"}}"#, e),
    };

    let mut guard = match INDEX.lock() {
        Ok(g) => g,
        Err(_) => return r#"{"error":"index lock poisoned"}"#.to_string(),
    };

    let index = match guard.as_mut() {
        Some(i) => i,
        None => return r#"{"error":"index not built"}"#.to_string(),
    };

    for file in &req.files {
        index.update_file(&file.path, &file.content, file.content_hash);
    }

    format!(r#"{{"updatedFiles":{}}}"#, req.files.len())
}

// ---------------------------------------------------------------------------
// FFI exports
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn solocode_trigram_index_build(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, handle_build)
}

#[no_mangle]
pub extern "C" fn solocode_trigram_search(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, handle_search)
}

#[no_mangle]
pub extern "C" fn solocode_trigram_update(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, handle_update)
}
