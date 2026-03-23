use crate::main_chat::auto_todo_support::{
    auto_todo_runtime_notes, auto_todo_title, linked_files_from_request, merged_linked_files,
    payload, preferred_active_form, preferred_title,
};
use app_core_protocol::main_chat_ui::{
    MainChatUiAutoTodoRuntimeState, MainChatUiIntentRequest, MainChatUiIntentResponse,
    MainChatUiState, MainChatUiTodoMutation, MainChatUiTodoPatch,
};

pub fn begin_runtime(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<(MainChatUiState, Vec<MainChatUiTodoPatch>), MainChatUiIntentResponse> {
    let assistant_message_id = required_payload(request, "assistant_message_id")?;
    let conversation_id = resolve_conversation_id(&state, request)?;
    if state.auto_todo_runtime_state_by_message.contains_key(&assistant_message_id) {
        return Ok((state, Vec::new()));
    }

    let title = auto_todo_title(request);
    let active_form = preferred_active_form("", payload(request, "immediate_label"), &title);
    let linked_files = linked_files_from_request(request);
    let todo_id = assistant_message_id.clone();
    state.auto_todo_runtime_state_by_message.insert(
        assistant_message_id.clone(),
        MainChatUiAutoTodoRuntimeState {
            todo_id: todo_id.clone(),
            conversation_id: conversation_id.clone(),
            title: title.clone(),
            active_form: active_form.clone(),
            linked_files: linked_files.clone(),
            operation_count: 0,
        },
    );

    Ok((state, vec![upsert_patch(
        todo_id,
        assistant_message_id,
        conversation_id,
        payload(request, "provider_id"),
        title,
        "in_progress".to_string(),
        auto_todo_runtime_notes(0),
        active_form,
        linked_files,
        true,
        request.timestamp,
    )]))
}

pub fn record_operation(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<(MainChatUiState, Vec<MainChatUiTodoPatch>), MainChatUiIntentResponse> {
    let assistant_message_id = required_payload(request, "assistant_message_id")?;
    let Some(existing) = state.auto_todo_runtime_state_by_message.get_mut(&assistant_message_id) else {
        return Ok((state, Vec::new()));
    };
    existing.operation_count += 1;
    existing.title = preferred_title(&existing.title, &auto_todo_title(request));
    existing.active_form = preferred_active_form(
        &existing.active_form,
        payload(request, "immediate_label"),
        &existing.title,
    );
    existing.linked_files = merged_linked_files(
        &existing.linked_files,
        &linked_files_from_request(request),
    );
    let todo_id = existing.todo_id.clone();
    let conversation_id = existing.conversation_id.clone();
    let title = existing.title.clone();
    let active_form = existing.active_form.clone();
    let linked_files = existing.linked_files.clone();
    let operation_count = existing.operation_count;

    Ok((state, vec![upsert_patch(
        todo_id,
        assistant_message_id,
        conversation_id,
        payload(request, "provider_id"),
        title,
        "in_progress".to_string(),
        auto_todo_runtime_notes(operation_count),
        active_form,
        linked_files,
        false,
        request.timestamp,
    )]))
}

pub fn finalize_runtime(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<(MainChatUiState, Vec<MainChatUiTodoPatch>), MainChatUiIntentResponse> {
    let assistant_message_id = required_payload(request, "assistant_message_id")?;
    let Some(existing) = state.auto_todo_runtime_state_by_message.remove(&assistant_message_id) else {
        return Ok((state, Vec::new()));
    };
    let (status, notes) = match payload(request, "outcome").as_str() {
        "success" => ("done".to_string(), "Auto-generated: all trace activities completed.".to_string()),
        "failed" | "aborted" => (
            "blocked".to_string(),
            "Auto-generated: execution interrupted or failed.".to_string(),
        ),
        _ => ("blocked".to_string(), "Auto-generated: status updated.".to_string()),
    };
    Ok((state, vec![
        status_patch(
            existing.todo_id.clone(),
            assistant_message_id.clone(),
            existing.conversation_id.clone(),
            payload(request, "provider_id"),
            existing.title,
            status,
            notes,
            existing.active_form,
            existing.linked_files,
            request.timestamp,
        ),
        clear_patch(assistant_message_id),
    ]))
}

pub fn discard_runtime(
    mut state: MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<(MainChatUiState, Vec<MainChatUiTodoPatch>), MainChatUiIntentResponse> {
    let assistant_message_id = required_payload(request, "assistant_message_id")?;
    let Some(existing) = state.auto_todo_runtime_state_by_message.remove(&assistant_message_id) else {
        return Ok((state, Vec::new()));
    };
    Ok((state, vec![
        MainChatUiTodoPatch {
            mutation: Some(MainChatUiTodoMutation::RemoveTodo),
            todo_id: Some(existing.todo_id),
            assistant_message_id: Some(assistant_message_id.clone()),
            conversation_id: Some(existing.conversation_id),
            provider_id: None,
            title: None,
            status: None,
            priority: None,
            notes: None,
            active_form: None,
            is_operational_placeholder: true,
            linked_files: Vec::new(),
            should_emit_trace_update: false,
            timestamp: request.timestamp,
        },
        clear_patch(assistant_message_id),
    ]))
}

fn upsert_patch(
    todo_id: String,
    assistant_message_id: String,
    conversation_id: String,
    provider_id: String,
    title: String,
    status: String,
    notes: String,
    active_form: String,
    linked_files: Vec<String>,
    should_emit_trace_update: bool,
    timestamp: Option<f64>,
) -> MainChatUiTodoPatch {
    MainChatUiTodoPatch {
        mutation: Some(MainChatUiTodoMutation::UpsertRuntimeTodo),
        todo_id: Some(todo_id),
        assistant_message_id: Some(assistant_message_id),
        conversation_id: Some(conversation_id),
        provider_id: Some(provider_id),
        title: Some(title),
        status: Some(status),
        priority: Some("medium".to_string()),
        notes: Some(notes),
        active_form: Some(active_form),
        is_operational_placeholder: true,
        linked_files,
        should_emit_trace_update,
        timestamp,
    }
}

fn status_patch(
    todo_id: String,
    assistant_message_id: String,
    conversation_id: String,
    provider_id: String,
    title: String,
    status: String,
    notes: String,
    active_form: String,
    linked_files: Vec<String>,
    timestamp: Option<f64>,
) -> MainChatUiTodoPatch {
    MainChatUiTodoPatch {
        mutation: Some(MainChatUiTodoMutation::SetStatus),
        todo_id: Some(todo_id),
        assistant_message_id: Some(assistant_message_id),
        conversation_id: Some(conversation_id),
        provider_id: Some(provider_id),
        title: Some(title),
        status: Some(status),
        priority: Some("medium".to_string()),
        notes: Some(notes),
        active_form: Some(active_form),
        is_operational_placeholder: true,
        linked_files,
        should_emit_trace_update: true,
        timestamp,
    }
}

fn clear_patch(assistant_message_id: String) -> MainChatUiTodoPatch {
    MainChatUiTodoPatch {
        mutation: Some(MainChatUiTodoMutation::ClearMessageRuntimeState),
        todo_id: None,
        assistant_message_id: Some(assistant_message_id),
        conversation_id: None,
        provider_id: None,
        title: None,
        status: None,
        priority: None,
        notes: None,
        active_form: None,
        is_operational_placeholder: true,
        linked_files: Vec::new(),
        should_emit_trace_update: false,
        timestamp: None,
    }
}

fn resolve_conversation_id(
    state: &MainChatUiState,
    request: &MainChatUiIntentRequest,
) -> Result<String, MainChatUiIntentResponse> {
    request
        .conversation_id
        .clone()
        .or_else(|| state.selected_conversation_id.clone())
        .or_else(|| request.payload.get("conversation_id").cloned())
        .ok_or_else(|| MainChatUiIntentResponse::error("missing_conversation_id", "conversationId is required"))
}

fn required_payload(
    request: &MainChatUiIntentRequest,
    key: &str,
) -> Result<String, MainChatUiIntentResponse> {
    request
        .payload
        .get(key)
        .cloned()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| MainChatUiIntentResponse::error("missing_payload", &format!("payload.{} is required", key)))
}
