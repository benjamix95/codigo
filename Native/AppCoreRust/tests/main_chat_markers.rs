use app_core_protocol::main_chat_markers::{MainChatMarkersRequest, MainChatMarkersResponse};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::{Path, PathBuf};

type MarkersFunction = unsafe extern "C" fn(*const c_char) -> *mut c_char;
type FreeFunction = unsafe extern "C" fn(*mut c_char);

const RTLD_NOW: c_int = 2;

unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn dlerror() -> *const c_char;
}

struct LoadedMarkersRuntime {
    handle: *mut c_void,
    markers: MarkersFunction,
    free_buffer: FreeFunction,
}

impl Drop for LoadedMarkersRuntime {
    fn drop(&mut self) {
        unsafe {
            let _ = dlclose(self.handle);
        }
    }
}

#[test]
fn ffi_markers_strip_coderide_markers_sanitizes_inline_payloads() {
    let runtime = load_runtime();
    let response = call(
        &runtime,
        MainChatMarkersRequest {
            schema_version: 1,
            operation: "strip_coderide_markers".to_string(),
            text: "markers:todo_write|files=README.md|Proceeding".to_string(),
            aggressive: Some(true),
        },
    );
    let text = response.text.expect("sanitized text");
    assert!(!text.contains("todo_write"));
    assert!(!text.contains("files=README.md"));
    assert!(text.contains("Proceeding"));
}

#[test]
fn ffi_markers_extracts_last_operational_thinking_line() {
    let runtime = load_runtime();
    let response = call(
        &runtime,
        MainChatMarkersRequest {
            schema_version: 1,
            operation: "extract_last_operational_thinking_line".to_string(),
            text: "Done\nExplored files\nReading config".to_string(),
            aggressive: None,
        },
    );
    assert_eq!(response.text.as_deref(), Some("Reading config"));
}

fn call(
    runtime: &LoadedMarkersRuntime,
    request: MainChatMarkersRequest,
) -> MainChatMarkersResponse {
    let raw_request = CString::new(serde_json::to_string(&request).expect("encode request"))
        .expect("request cstring");
    let raw_response = unsafe { (runtime.markers)(raw_request.as_ptr()) };
    assert!(!raw_response.is_null(), "markers runtime returned null");
    let encoded = unsafe { CStr::from_ptr(raw_response) }
        .to_str()
        .expect("utf8 response")
        .to_string();
    unsafe {
        (runtime.free_buffer)(raw_response);
    }
    serde_json::from_str(&encoded).expect("decode response")
}

fn load_runtime() -> LoadedMarkersRuntime {
    let dylib_path = runtime_library_path();
    let path = CString::new(dylib_path.to_string_lossy().to_string()).expect("path cstring");
    let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW) };
    assert!(!handle.is_null(), "dlopen failed: {}", last_dlerror());
    let markers = load_symbol::<MarkersFunction>(handle, "chat_core_markers_handle");
    let free_buffer = load_symbol::<FreeFunction>(handle, "solocode_free_buffer");
    LoadedMarkersRuntime {
        handle,
        markers,
        free_buffer,
    }
}

fn load_symbol<T>(handle: *mut c_void, symbol: &str) -> T {
    let symbol = CString::new(symbol).expect("symbol cstring");
    let raw = unsafe { dlsym(handle, symbol.as_ptr()) };
    assert!(
        !raw.is_null(),
        "dlsym failed for {}: {}",
        symbol.to_string_lossy(),
        last_dlerror()
    );
    unsafe { std::mem::transmute_copy(&raw) }
}

fn runtime_library_path() -> PathBuf {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let preferred = manifest_dir.join("../target/debug/libsolocode_rust_core.dylib");
    if preferred.exists() {
        return preferred;
    }
    manifest_dir.join("../RustCore/build/lib/libsolocode_rust_core.dylib")
}

fn last_dlerror() -> String {
    let ptr = unsafe { dlerror() };
    if ptr.is_null() {
        "unknown dlerror".to_string()
    } else {
        unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned()
    }
}
