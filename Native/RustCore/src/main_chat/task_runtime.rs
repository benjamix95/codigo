use app_core_protocol::main_chat_task_runtime::{
    MainChatTaskRuntimeRequest, MainChatTaskRuntimeResponse, MainChatTaskRuntimeState,
    MainChatTaskStateSnapshot,
};

pub fn handle_task_runtime_action(
    request: MainChatTaskRuntimeRequest,
) -> MainChatTaskRuntimeResponse {
    if request.schema_version != 1 {
        return MainChatTaskRuntimeResponse::error(
            "unsupported_schema",
            "schemaVersion must be 1",
        );
    }

    match request.operation.as_str() {
        "begin_task" => begin_task(request),
        "end_task" => end_task(request),
        "set_task_status" => set_task_status(request),
        _ => MainChatTaskRuntimeResponse::error(
            "unsupported_operation",
            "Unsupported task runtime operation",
        ),
    }
}

fn begin_task(request: MainChatTaskRuntimeRequest) -> MainChatTaskRuntimeResponse {
    let Some(conversation_id) = request.conversation_id else {
        return MainChatTaskRuntimeResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let mut state = request.state;
    if let Some(index) = task_index(&state, &conversation_id) {
        state.task_states[index].started_at = request.started_at.or(state.task_states[index].started_at);
        state.task_states[index].status_text = "Thinking".to_string();
    } else {
        state.task_states.push(MainChatTaskStateSnapshot {
            conversation_id,
            started_at: request.started_at,
            status_text: "Thinking".to_string(),
        });
    }
    MainChatTaskRuntimeResponse::success(sorted_state(state))
}

fn end_task(request: MainChatTaskRuntimeRequest) -> MainChatTaskRuntimeResponse {
    let Some(conversation_id) = request.conversation_id else {
        return MainChatTaskRuntimeResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let mut state = request.state;
    state.task_states.retain(|item| item.conversation_id != conversation_id);
    MainChatTaskRuntimeResponse::success(sorted_state(state))
}

fn set_task_status(request: MainChatTaskRuntimeRequest) -> MainChatTaskRuntimeResponse {
    let Some(conversation_id) = request.conversation_id else {
        return MainChatTaskRuntimeResponse::error(
            "missing_conversation_id",
            "conversationId is required",
        );
    };
    let Some(status_text) = request.status_text else {
        return MainChatTaskRuntimeResponse::error("missing_status_text", "statusText is required");
    };
    let mut state = request.state;
    if let Some(index) = task_index(&state, &conversation_id) {
        state.task_states[index].status_text = status_text;
    }
    MainChatTaskRuntimeResponse::success(sorted_state(state))
}

fn task_index(state: &MainChatTaskRuntimeState, conversation_id: &str) -> Option<usize> {
    state
        .task_states
        .iter()
        .position(|item| item.conversation_id == conversation_id)
}

fn sorted_state(mut state: MainChatTaskRuntimeState) -> MainChatTaskRuntimeState {
    state.task_states.sort_by(|lhs, rhs| {
        lhs.started_at
            .partial_cmp(&rhs.started_at)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| lhs.conversation_id.cmp(&rhs.conversation_id))
    });
    state
}

#[cfg(test)]
mod tests {
    use super::*;
    use app_core_protocol::main_chat_task_runtime::{
        MainChatTaskRuntimeRequest, MainChatTaskRuntimeState, MainChatTaskStateSnapshot,
    };

    #[test]
    fn begin_task_sets_default_status_and_start_time() {
        let response = handle_task_runtime_action(MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "begin_task".to_string(),
            state: MainChatTaskRuntimeState::default(),
            conversation_id: Some("conv-a".to_string()),
            status_text: None,
            started_at: Some(10.0),
        });
        let state = response.state.expect("state");
        assert_eq!(state.task_states.len(), 1);
        assert_eq!(state.task_states[0].status_text, "Thinking");
        assert_eq!(state.task_states[0].started_at, Some(10.0));
    }

    #[test]
    fn end_task_removes_only_matching_conversation() {
        let response = handle_task_runtime_action(MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "end_task".to_string(),
            state: MainChatTaskRuntimeState {
                task_states: vec![
                    MainChatTaskStateSnapshot {
                        conversation_id: "conv-a".to_string(),
                        started_at: Some(1.0),
                        status_text: "Thinking".to_string(),
                    },
                    MainChatTaskStateSnapshot {
                        conversation_id: "conv-b".to_string(),
                        started_at: Some(2.0),
                        status_text: "Running".to_string(),
                    },
                ],
            },
            conversation_id: Some("conv-b".to_string()),
            status_text: None,
            started_at: None,
        });
        let state = response.state.expect("state");
        assert_eq!(state.task_states.len(), 1);
        assert_eq!(state.task_states[0].conversation_id, "conv-a");
    }

    #[test]
    fn set_task_status_updates_existing_task() {
        let response = handle_task_runtime_action(MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "set_task_status".to_string(),
            state: MainChatTaskRuntimeState {
                task_states: vec![MainChatTaskStateSnapshot {
                    conversation_id: "conv-a".to_string(),
                    started_at: Some(1.0),
                    status_text: "Thinking".to_string(),
                }],
            },
            conversation_id: Some("conv-a".to_string()),
            status_text: Some("Testing".to_string()),
            started_at: None,
        });
        let state = response.state.expect("state");
        assert_eq!(state.task_states[0].status_text, "Testing");
    }

    #[test]
    fn set_task_status_does_not_create_missing_task() {
        let response = handle_task_runtime_action(MainChatTaskRuntimeRequest {
            schema_version: 1,
            operation: "set_task_status".to_string(),
            state: MainChatTaskRuntimeState::default(),
            conversation_id: Some("conv-a".to_string()),
            status_text: Some("Testing".to_string()),
            started_at: None,
        });
        let state = response.state.expect("state");
        assert!(state.task_states.is_empty());
    }
}
