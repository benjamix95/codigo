use super::{handle_ui_intent, project_ui};
use app_core_protocol::main_chat::{MainChatArtifact, MainChatArtifactKind, MainChatTurnState};
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanSnapshot, MainChatRuntimeOutput, MainChatRuntimeSnapshot,
};
use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot, MainChatStorePlanBoardSnapshot,
    MainChatStorePlanOptionSnapshot, MainChatStorePlanStepSnapshot, MainChatStoreSnapshot,
};
use app_core_protocol::main_chat_task_runtime::{
    MainChatTaskRuntimeState, MainChatTaskStateSnapshot,
};
use app_core_protocol::main_chat_ui::{
    MainChatUiIntentRequest, MainChatUiProjectRequest, MainChatUiState,
};

#[test]
fn ui_projection_merges_runtime_state_plan_and_task_flags() {
    let response = project_ui(MainChatUiProjectRequest {
        schema_version: 1,
        state: base_ui_state(),
    });
    let snapshot = response.snapshot.expect("snapshot");
    assert_eq!(snapshot.selected_conversation_id.as_deref(), Some("conv-1"));
    assert_eq!(snapshot.messages.len(), 1);
    assert_eq!(snapshot.messages[0].primary_text.as_deref(), Some("Hello world"));
    assert!(snapshot.messages[0].timeline_blocks.iter().any(|block| block.kind == "status"));
    assert!(snapshot.task.is_loading);
    assert_eq!(snapshot.task.status_text.as_deref(), Some("Running"));
    assert_eq!(snapshot.plan.phase, Some(MainChatPlanPhase::ProposalReady));
    assert!(snapshot.plan.is_visible);
    assert!(snapshot.plan.should_hide_markdown);
    assert!(snapshot.composer.can_cancel);
}

#[test]
fn ui_intent_choose_plan_option_updates_store_and_runtime_phase() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "choose_plan_option".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("Option A".to_string()),
        timestamp: Some(42.0),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let snapshot = response.snapshot.expect("snapshot");
    assert_eq!(
        state
            .store_snapshot
            .plan_boards
            .get("conv-1")
            .and_then(|board| board.chosen_path.as_deref()),
        Some("Option A")
    );
    assert_eq!(
        state
            .runtime_snapshot
            .as_ref()
            .and_then(|runtime| runtime.plan.as_ref())
            .and_then(|plan| plan.phase.clone()),
        Some(MainChatPlanPhase::ReadyToBuild)
    );
    assert_eq!(snapshot.plan.chosen_path.as_deref(), Some("Option A"));
}

#[test]
fn ui_intent_stream_replace_text_syncs_runtime_text_into_store_snapshot() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "stream_replace_text".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("ignored because runtime owns the latest text".to_string()),
        timestamp: Some(42.0),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0].primary_text_snapshot.as_deref(),
        Some("Hello world")
    );
    assert!(state.store_snapshot.conversations[0].messages[0].is_streaming);
}

#[test]
fn ui_intent_stream_finish_marks_store_message_not_streaming() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "stream_finish_success".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(42.0),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert!(!state.store_snapshot.conversations[0].messages[0].is_streaming);
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
            plan_boards: [(
                "conv-1".to_string(),
                MainChatStorePlanBoardSnapshot {
                    goal: "Ship cutover".to_string(),
                    options: vec![MainChatStorePlanOptionSnapshot {
                        id: 1,
                        title: "Option A".to_string(),
                        full_text: "Option A".to_string(),
                    }],
                    chosen_path: None,
                    steps: vec![MainChatStorePlanStepSnapshot {
                        id: "step-1".to_string(),
                        title: "Add boundary".to_string(),
                        description: "Create protocol".to_string(),
                        target_file: None,
                        status: "pending".to_string(),
                        linked_files: vec![],
                        depends_on: vec![],
                        notes: String::new(),
                        updated_at: None,
                    }],
                    updated_at: None,
                    walkthrough_markdown: Some("Plan".to_string()),
                    walkthrough_summary: None,
                    walkthrough_outcome: None,
                },
            )]
            .into_iter()
            .collect(),
        },
        runtime_snapshot: Some(MainChatRuntimeSnapshot {
            turn_state: MainChatTurnState {
                conversation_id: "conv-1".to_string(),
                assistant_message_id: "msg-1".to_string(),
                turn_id: "turn-1".to_string(),
                status: "streaming".to_string(),
                is_streaming: true,
                ordered_text_stream_ids: vec!["main".to_string()],
                text_by_stream_id: [("main".to_string(), "Hello world".to_string())].into_iter().collect(),
                artifacts: vec![MainChatArtifact {
                    id: "status-1".to_string(),
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
                phase: Some(MainChatPlanPhase::ProposalReady),
                proposal_content: Some("Plan body".to_string()),
                option_full_texts: vec!["Option A".to_string()],
                should_run_inline: true,
                ..Default::default()
            }),
            output: Some(MainChatRuntimeOutput {
                should_open_plan_panel: true,
                should_hide_plan_markdown: true,
                ..Default::default()
            }),
        }),
        task_runtime_state: Some(MainChatTaskRuntimeState {
            task_states: vec![MainChatTaskStateSnapshot {
                conversation_id: "conv-1".to_string(),
                started_at: Some(12.0),
                status_text: "Running".to_string(),
            }],
        }),
        selected_conversation_id: Some("conv-1".to_string()),
        draft_text: "continue".to_string(),
        plan_panel_visible: false,
        follow_live: true,
        collapsed_artifact_ids_by_turn: Default::default(),
    }
}
