use app_core_protocol::main_chat_task_runtime::{
    MainChatTaskRuntimeRequest, MainChatTaskRuntimeResponse, MainChatTaskRuntimeState,
    MainChatTaskStateSnapshot,
};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::{Path, PathBuf};

type RuntimeFunction = unsafe extern "C" fn(*const c_char) -> *mut c_char;
type FreeFunction = unsafe extern "C" fn(*mut c_char);

const RTLD_NOW: c_int = 2;

unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn dlerror() -> *const c_char;
}

struct LoadedRuntime {
    handle: *mut c_void,
    task_runtime: RuntimeFunction,
    free_buffer: FreeFunction,
}

impl Drop for LoadedRuntime {
    fn drop(&mut self) {
        unsafe {
            let _ = dlclose(self.handle);
        }
    }
}

#[test]
fn ffi_task_runtime_handles_begin_end_and_status_flow() {
    let runtime = load_runtime();

    let begin = call_task_runtime(
        &runtime,
        MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "begin_task".to_string(),
            state: MainChatTaskRuntimeState::default(),
            conversation_id: Some("conv-a".to_string()),
            status_text: None,
            started_at: Some(10.0),
        },
    );
    let mut state = begin.state.expect("state after begin");
    assert_eq!(state.task_states.len(), 1);
    assert_eq!(state.task_states[0].status_text, "Thinking");

    let update = call_task_runtime(
        &runtime,
        MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "set_task_status".to_string(),
            state: state.clone(),
            conversation_id: Some("conv-a".to_string()),
            status_text: Some("Running tests".to_string()),
            started_at: None,
        },
    );
    state = update.state.expect("state after status");
    assert_eq!(state.task_states[0].status_text, "Running tests");

    let end = call_task_runtime(
        &runtime,
        MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "end_task".to_string(),
            state,
            conversation_id: Some("conv-a".to_string()),
            status_text: None,
            started_at: None,
        },
    );
    assert!(end
        .state
        .expect("state after end")
        .task_states
        .iter()
        .all(|item| item.conversation_id != "conv-a"));
}

#[test]
fn ffi_task_runtime_status_update_does_not_create_missing_task() {
    let runtime = load_runtime();

    let response = call_task_runtime(
        &runtime,
        MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "set_task_status".to_string(),
            state: MainChatTaskRuntimeState {
                task_states: vec![MainChatTaskStateSnapshot {
                    conversation_id: "conv-a".to_string(),
                    started_at: Some(1.0),
                    status_text: "Thinking".to_string(),
                }],
            },
            conversation_id: Some("conv-b".to_string()),
            status_text: Some("Should not appear".to_string()),
            started_at: None,
        },
    );
    let state = response.state.expect("state");
    assert_eq!(state.task_states.len(), 1);
    assert_eq!(state.task_states[0].conversation_id, "conv-a");
    assert_eq!(state.task_states[0].status_text, "Thinking");
}

fn call_task_runtime(
    runtime: &LoadedRuntime,
    request: MainChatTaskRuntimeRequest,
) -> MainChatTaskRuntimeResponse {
    let raw_request = CString::new(serde_json::to_string(&request).expect("encode request"))
        .expect("request cstring");
    let raw_response = unsafe { (runtime.task_runtime)(raw_request.as_ptr()) };
    assert!(!raw_response.is_null(), "task runtime returned null");
    let encoded = unsafe { CStr::from_ptr(raw_response) }
        .to_str()
        .expect("utf8 response")
        .to_string();
    unsafe {
        (runtime.free_buffer)(raw_response);
    }
    serde_json::from_str(&encoded).expect("decode response")
}

fn load_runtime() -> LoadedRuntime {
    let dylib_path = runtime_library_path();
    let path = CString::new(dylib_path.to_string_lossy().to_string()).expect("path cstring");
    let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW) };
    assert!(
        !handle.is_null(),
        "dlopen failed for {}: {}",
        dylib_path.display(),
        last_dlerror()
    );

    let task_runtime =
        load_symbol::<RuntimeFunction>(handle, "chat_core_task_runtime_handle_action");
    let free_buffer = load_symbol::<FreeFunction>(handle, "solocode_free_buffer");
    LoadedRuntime {
        handle,
        task_runtime,
        free_buffer,
    }
}

fn load_symbol<T>(handle: *mut c_void, symbol: &str) -> T {
    let symbol = CString::new(symbol).expect("symbol cstring");
    let raw = unsafe { dlsym(handle, symbol.as_ptr()) };
    assert!(
        !raw.is_null(),
        "dlsym failed for symbol {}: {}",
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
    let fallback = manifest_dir.join("../RustCore/build/lib/libsolocode_rust_core.dylib");
    assert!(
        fallback.exists(),
        "RustCore dylib non trovata in {} o {}",
        preferred.display(),
        fallback.display()
    );
    fallback
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
