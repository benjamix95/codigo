use app_core_protocol::main_chat::{MainChatArtifact, MainChatArtifactKind, MainChatTurnState};
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanSnapshot, MainChatRuntimeOutput, MainChatRuntimeSnapshot,
};
use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot, MainChatStoreSnapshot,
};
use app_core_protocol::main_chat_task_runtime::{
    MainChatTaskRuntimeState, MainChatTaskStateSnapshot,
};
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiIntentResponse, MainChatUiProjectRequest,
    MainChatUiProjectResponse, MainChatUiState,
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
    project_ui: RuntimeFunction,
    handle_intent: RuntimeFunction,
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
fn ffi_ui_project_returns_selected_conversation_snapshot() {
    let runtime = load_runtime();
    let response = call_project(&runtime, MainChatUiProjectRequest {
        schema_version: 1,
        state: base_ui_state(),
    });
    let snapshot = response.snapshot.expect("snapshot");
    assert_eq!(snapshot.selected_conversation_id.as_deref(), Some("conv-1"));
    assert_eq!(snapshot.messages[0].primary_text.as_deref(), Some("Hello from Rust"));
    assert!(snapshot.task.is_loading);
}

#[test]
fn ffi_ui_handle_intent_can_toggle_collapsed_artifact() {
    let runtime = load_runtime();
    let response = call_intent(&runtime, MainChatUiIntentRequest {
        schema_version: 1,
        intent: "toggle_artifact_collapsed".to_string(),
        state: base_ui_state(),
        conversation_id: None,
        turn_id: Some("turn-1".to_string()),
        artifact_id: Some("artifact-1".to_string()),
        text: None,
        timestamp: None,
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert_eq!(
        state.collapsed_artifact_ids_by_turn.get("turn-1"),
        Some(&vec!["artifact-1".to_string()])
    );
}

#[test]
fn ffi_ui_handle_intent_stream_finish_marks_message_not_streaming() {
    let runtime = load_runtime();
    let response = call_intent(&runtime, MainChatUiIntentRequest {
        schema_version: 1,
        intent: "stream_finish_success".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("Final answer".to_string()),
        timestamp: Some(2.0),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert!(!state.store_snapshot.conversations[0].messages[0].is_streaming);
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0].primary_text_snapshot.as_deref(),
        Some("Final answer")
    );
}

#[test]
fn ffi_ui_handle_intent_plan_questions_raise_epoch_and_open_panel() {
    let runtime = load_runtime();
    let response = call_intent(&runtime, MainChatUiIntentRequest {
        schema_version: 1,
        intent: "plan_receive_clarification_questions".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("## Questions\n- Which phase should move first?".to_string()),
        timestamp: Some(2.0),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let snapshot = response.snapshot.expect("snapshot");
    assert!(state.plan_panel_visible);
    assert_eq!(snapshot.plan.question_epoch, 1);
    assert_eq!(
        snapshot.plan.clarification_questions.as_deref(),
        Some("## Questions\n- Which phase should move first?")
    );
}

#[test]
fn ffi_ui_handle_intent_auto_todo_begin_and_discard_emit_patches() {
    let runtime = load_runtime();
    let begin = call_intent(&runtime, MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_begin_runtime".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(2.0),
        payload: [
            ("assistant_message_id".to_string(), "00000000-0000-0000-0000-000000000002".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
            ("path".to_string(), "Sources/App.swift".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert_eq!(begin.todo_patches.len(), 1);
    assert_eq!(begin.todo_patches[0].title.as_deref(), Some("Complete changes on App.swift"));

    let discard = call_intent(&runtime, MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_discard_runtime".to_string(),
        state: begin.state.expect("state"),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(3.0),
        payload: [
            ("assistant_message_id".to_string(), "00000000-0000-0000-0000-000000000002".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert_eq!(discard.todo_patches.len(), 2);
}

fn call_project(runtime: &LoadedRuntime, request: MainChatUiProjectRequest) -> MainChatUiProjectResponse {
    let raw_request = CString::new(serde_json::to_string(&request).expect("encode request"))
        .expect("request cstring");
    let raw_response = unsafe { (runtime.project_ui)(raw_request.as_ptr()) };
    let encoded = decode_raw_response(raw_response, runtime.free_buffer);
    serde_json::from_str(&encoded).expect("decode project response")
}

fn call_intent(runtime: &LoadedRuntime, request: MainChatUiIntentRequest) -> MainChatUiIntentResponse {
    let raw_request = CString::new(serde_json::to_string(&request).expect("encode request"))
        .expect("request cstring");
    let raw_response = unsafe { (runtime.handle_intent)(raw_request.as_ptr()) };
    let encoded = decode_raw_response(raw_response, runtime.free_buffer);
    serde_json::from_str(&encoded).expect("decode intent response")
}

fn decode_raw_response(
    raw_response: *mut c_char,
    free: FreeFunction,
) -> String {
    assert!(!raw_response.is_null(), "ui runtime returned null");
    let encoded = unsafe { CStr::from_ptr(raw_response) }
        .to_str()
        .expect("utf8 response")
        .to_string();
    unsafe {
        free(raw_response);
    }
    encoded
}

fn load_runtime() -> LoadedRuntime {
    let dylib_path = runtime_library_path();
    let path = CString::new(dylib_path.to_string_lossy().to_string()).expect("path cstring");
    let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW) };
    assert!(!handle.is_null(), "dlopen failed: {}", last_dlerror());
    LoadedRuntime {
        handle,
        project_ui: load_symbol::<RuntimeFunction>(handle, "chat_core_ui_project"),
        handle_intent: load_symbol::<RuntimeFunction>(handle, "chat_core_ui_handle_intent"),
        free_buffer: load_symbol::<FreeFunction>(handle, "solocode_free_buffer"),
    }
}

fn load_symbol<T>(handle: *mut c_void, symbol: &str) -> T {
    let symbol = CString::new(symbol).expect("symbol cstring");
    let raw = unsafe { dlsym(handle, symbol.as_ptr()) };
    assert!(!raw.is_null(), "dlsym failed for {}: {}", symbol.to_string_lossy(), last_dlerror());
    unsafe { std::mem::transmute_copy(&raw) }
}

fn runtime_library_path() -> PathBuf {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let preferred = manifest_dir.join("../target/debug/libsolocode_rust_core.dylib");
    if preferred.exists() {
        return preferred;
    }
    let fallback = manifest_dir.join("../RustCore/build/lib/libsolocode_rust_core.dylib");
    assert!(fallback.exists(), "RustCore dylib non trovata");
    fallback
}

fn last_dlerror() -> String {
    let ptr = unsafe { dlerror() };
    if ptr.is_null() {
        "unknown dlerror".to_string()
    } else {
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
    }
}

fn base_ui_state() -> MainChatUiState {
    MainChatUiState {
        store_snapshot: MainChatStoreSnapshot {
            conversations: vec![MainChatStoreConversationSnapshot {
                id: "conv-1".to_string(),
                thread_root_conversation_id: "conv-1".to_string(),
                title: "Main".to_string(),
                messages: vec![MainChatStoreMessageSnapshot {
                    id: "msg-1".to_string(),
                    role: "assistant".to_string(),
                    content: "Hello".to_string(),
                    primary_text_snapshot: Some("Hello".to_string()),
                    blocks: None,
                    turn_metadata: None,
                    is_streaming: true,
                    image_paths: None,
                    attachments: None,
                    plan_attachment: None,
                    reasoning_text: None,
                    subagent_cards: None,
                }],
                created_at: None,
                context_id: None,
                context_folder_path: None,
                mode: Some("Agent".to_string()),
                preferred_provider_id: Some("codex".to_string()),
                context_memory_summary_markdown: None,
                context_memory_generated_at: None,
                context_memory_source_message_count: None,
                is_archived: false,
                is_pinned: false,
                is_favorite: false,
                last_input_tokens: None,
                workspace_id: None,
                ad_hoc_folder_paths: vec![],
                checkpoints: vec![],
            }],
            plan_boards: Default::default(),
        },
        runtime_snapshot: Some(MainChatRuntimeSnapshot {
            turn_state: MainChatTurnState {
                conversation_id: "conv-1".to_string(),
                assistant_message_id: "msg-1".to_string(),
                turn_id: "turn-1".to_string(),
                status: "streaming".to_string(),
                is_streaming: true,
                ordered_text_stream_ids: vec!["main".to_string()],
                text_by_stream_id: [("main".to_string(), "Hello from Rust".to_string())].into_iter().collect(),
                artifacts: vec![MainChatArtifact {
                    id: "artifact-1".to_string(),
                    kind: MainChatArtifactKind::Status,
                    title: "Status".to_string(),
                    text: "Running".to_string(),
                    items: vec![],
                    metadata: Default::default(),
                    is_collapsible: true,
                    is_collapsed_by_default: false,
                }],
                ..Default::default()
            },
            mode: None,
            direct_stream: None,
            plan: Some(MainChatPlanSnapshot {
                phase: Some(MainChatPlanPhase::Idle),
                ..Default::default()
            }),
            output: Some(MainChatRuntimeOutput::default()),
        }),
        task_runtime_state: Some(MainChatTaskRuntimeState {
            task_states: vec![MainChatTaskStateSnapshot {
                conversation_id: "conv-1".to_string(),
                started_at: Some(1.0),
                status_text: "Running".to_string(),
            }],
        }),
        selected_conversation_id: Some("conv-1".to_string()),
        draft_text: String::new(),
        plan_panel_visible: false,
        follow_live: true,
        collapsed_artifact_ids_by_turn: Default::default(),
        auto_todo_runtime_state_by_message: Default::default(),
    }
}
