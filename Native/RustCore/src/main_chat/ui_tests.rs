use super::{handle_ui_intent, project_ui};
use app_core_protocol::main_chat::{
    MainChatArtifact, MainChatArtifactKind, MainChatEvent, MainChatEventKind, MainChatTurnState,
};
use app_core_protocol::main_chat_runtime::{
    MainChatPlanPhase, MainChatPlanSnapshot, MainChatRuntimeOutput, MainChatRuntimeSnapshot,
};
use app_core_protocol::main_chat_store::{
    MainChatStoreConversationSnapshot, MainChatStoreMessageSnapshot,
    MainChatStorePlanBoardSnapshot, MainChatStorePlanOptionSnapshot, MainChatStorePlanStepSnapshot,
    MainChatStoreSnapshot,
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
    assert_eq!(
        snapshot.messages[0].primary_text.as_deref(),
        Some("Hello world")
    );
    assert!(snapshot.messages[0]
        .timeline_blocks
        .iter()
        .any(|block| block.kind == "status"));
    assert!(snapshot.task.is_loading);
    assert_eq!(snapshot.task.status_text.as_deref(), Some("Running"));
    assert_eq!(snapshot.plan.phase, Some(MainChatPlanPhase::ProposalReady));
    assert!(snapshot.plan.is_visible);
    assert!(snapshot.plan.should_hide_markdown);
    assert!(snapshot.composer.can_cancel);
}

#[test]
fn ui_intent_choose_plan_option_updates_store_and_runtime_phase() {
    let choice = "## Option A: Rust cutover\n## Todo\n- [ ] Move parser".to_string();
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "choose_plan_option".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some(choice.clone()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
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
        Some(choice.as_str())
    );
    assert_eq!(
        state
            .runtime_snapshot
            .as_ref()
            .and_then(|runtime| runtime.plan.as_ref())
            .and_then(|plan| plan.phase.clone()),
        Some(MainChatPlanPhase::ReadyToBuild)
    );
    assert_eq!(snapshot.plan.chosen_path.as_deref(), Some(choice.as_str()));
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
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0]
            .primary_text_snapshot
            .as_deref(),
        Some("Hello world")
    );
    assert!(state.store_snapshot.conversations[0].messages[0].is_streaming);
}

#[test]
fn ui_intent_stream_replace_text_does_not_overwrite_previous_assistant_when_runtime_target_is_stale(
) {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "stream_replace_text".to_string(),
        state: stale_runtime_target_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("ignored because runtime target is stale".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let conversation = &state.store_snapshot.conversations[0];
    assert_eq!(
        conversation.messages[0].primary_text_snapshot.as_deref(),
        Some("Older answer")
    );
    assert_eq!(
        conversation.messages[1].primary_text_snapshot.as_deref(),
        Some("")
    );
    assert_eq!(conversation.messages[1].content, "");
}

#[test]
fn ui_intent_stream_replace_text_preserves_interleaved_runtime_segments() {
    let mut state = base_ui_state();
    if let Some(runtime) = state.runtime_snapshot.as_mut() {
        runtime.turn_state.text_segments = vec!["Prima parte".to_string()];
        runtime.turn_state.timeline_segments = vec![
            app_core_protocol::main_chat::TimelineSegment {
                kind: app_core_protocol::main_chat::TimelineSegmentKind::Text,
                index: 0,
                sequence: 0,
            },
            app_core_protocol::main_chat::TimelineSegment {
                kind: app_core_protocol::main_chat::TimelineSegmentKind::ToolUse,
                index: 0,
                sequence: 1,
            },
        ];
        runtime.turn_state.timeline_next_sequence = 2;
        runtime.turn_state.text_by_stream_id =
            [("main".to_string(), "Prima parte".to_string())].into_iter().collect();
    }

    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "stream_replace_text".to_string(),
        state,
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("Prima parteSeconda parte".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let message = &state.store_snapshot.conversations[0].messages[0];
    let blocks = message.blocks.as_ref().expect("blocks");
    let kinds: Vec<_> = blocks.iter().map(|block| block.kind.as_str()).collect();
    let primary_texts: Vec<_> = blocks
        .iter()
        .filter(|block| block.kind == "primaryText")
        .map(|block| block.text.as_str())
        .collect();
    assert_eq!(kinds, vec!["primaryText", "toolMarker", "primaryText", "status"]);
    assert_eq!(primary_texts, vec!["Prima parte", "Seconda parte"]);
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
        text: Some("Final answer".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    assert!(!state.store_snapshot.conversations[0].messages[0].is_streaming);
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0]
            .primary_text_snapshot
            .as_deref(),
        Some("Final answer")
    );
}

#[test]
fn ui_intent_plan_receive_clarification_questions_updates_epoch_and_visibility() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "plan_receive_clarification_questions".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("## Questions\n- What should we cut over first?".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let snapshot = response.snapshot.expect("snapshot");
    assert!(state.plan_panel_visible);
    assert_eq!(
        state
            .runtime_snapshot
            .as_ref()
            .and_then(|runtime| runtime.plan.as_ref())
            .and_then(|plan| plan.planning_state_kind.clone()),
        Some(
            app_core_protocol::main_chat_runtime::MainChatPlanningStateKind::AwaitingClarification
        )
    );
    assert_eq!(snapshot.plan.question_epoch, 1);
    assert!(snapshot.plan.is_visible);
    assert_eq!(
        snapshot.plan.clarification_questions.as_deref(),
        Some("## Questions\n- What should we cut over first?")
    );
}

#[test]
fn ui_intent_apply_plan_runtime_action_projects_prompt_and_panel_state() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "apply_plan_runtime_action".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("Ship Rust planning boundary".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [(
            "action".to_string(),
            "plan_prepare_phase1_analysis_prompt".to_string(),
        )]
        .into_iter()
        .collect(),
    });
    let state = response.state.expect("state");
    let snapshot = response.snapshot.expect("snapshot");
    assert!(state.plan_panel_visible);
    assert_eq!(snapshot.plan.phase, Some(MainChatPlanPhase::Analyzing));
    assert_eq!(
        state
            .runtime_snapshot
            .as_ref()
            .and_then(|runtime| runtime.output.as_ref())
            .and_then(|output| output.generated_prompt.as_ref())
            .map(|prompt| prompt.contains("Phase: Codebase Analysis")),
        Some(true)
    );
}

#[test]
fn ui_intent_plan_phase0_screening_seeds_runtime_when_snapshot_missing() {
    let mut state = base_ui_state();
    state.runtime_snapshot = None;
    state.selected_conversation_id = Some("conv-1".to_string());
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "apply_plan_runtime_action".to_string(),
        state,
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("First plan request without prior stream snapshot".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            (
                "action".to_string(),
                "plan_prepare_phase0_screening_prompt".to_string(),
            ),
            ("should_run_inline".to_string(), "true".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert!(
        response.error.is_none(),
        "unexpected error: {:?}",
        response.error
    );
    let state = response.state.expect("state");
    let generated = state
        .runtime_snapshot
        .as_ref()
        .and_then(|runtime| runtime.output.as_ref())
        .and_then(|output| output.generated_prompt.as_ref());
    assert!(
        generated.is_some_and(|prompt| !prompt.trim().is_empty()),
        "phase0 screening prompt should be generated, got: {:?}",
        generated
    );
}

#[test]
fn ui_intent_plan_phase0_request_conversation_overrides_stale_selected_conversation() {
    let mut state = base_ui_state();
    state.runtime_snapshot = None;
    state.selected_conversation_id = Some("conv-stale".to_string());
    state.store_snapshot.conversations.push(MainChatStoreConversationSnapshot {
        id: "conv-2".to_string(),
        thread_root_conversation_id: "conv-2".to_string(),
        title: "Second".to_string(),
        messages: Vec::new(),
        created_at: None,
        context_id: None,
        context_folder_path: None,
        mode: Some("Agent".to_string()),
        preferred_provider_id: None,
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
    });
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "apply_plan_runtime_action".to_string(),
        state,
        conversation_id: Some("conv-2".to_string()),
        turn_id: None,
        artifact_id: None,
        text: Some("Plan request should target the explicit conversation".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            (
                "action".to_string(),
                "plan_prepare_phase0_screening_prompt".to_string(),
            ),
            ("should_run_inline".to_string(), "true".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert!(
        response.error.is_none(),
        "unexpected error: {:?}",
        response.error
    );
    let state = response.state.expect("state");
    let snapshot = response.snapshot.expect("snapshot");
    assert_eq!(state.selected_conversation_id.as_deref(), Some("conv-2"));
    assert_eq!(snapshot.selected_conversation_id.as_deref(), Some("conv-2"));
    assert_eq!(
        state
            .runtime_snapshot
            .as_ref()
            .map(|runtime| runtime.turn_state.conversation_id.as_str()),
        Some("conv-2")
    );
}

#[test]
fn ui_intent_plan_phase0_requires_conversation_when_no_runtime_snapshot() {
    let mut state = base_ui_state();
    state.runtime_snapshot = None;
    state.selected_conversation_id = None;
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "apply_plan_runtime_action".to_string(),
        state,
        conversation_id: None,
        turn_id: None,
        artifact_id: None,
        text: Some("request".to_string()),
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            (
                "action".to_string(),
                "plan_prepare_phase0_screening_prompt".to_string(),
            ),
            ("should_run_inline".to_string(), "true".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert_eq!(
        response.error.as_ref().map(|e| e.code.as_str()),
        Some("missing_conversation_for_plan")
    );
}

#[test]
fn ui_intent_pipeline_apply_event_syncs_runtime_and_store_snapshot() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "pipeline_apply_event".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(42.0),
        pipeline_event: Some(MainChatEvent {
            id: "pipeline-1".to_string(),
            conversation_id: "conv-1".to_string(),
            assistant_message_id: "msg-1".to_string(),
            turn_id: "turn-1".to_string(),
            sequence: 2,
            source: "pipeline".to_string(),
            kind: MainChatEventKind::TextReplace,
            payload: [("replacement".to_string(), "Pipeline text".to_string())]
                .into_iter()
                .collect(),
            timestamp: 42.0,
        }),
        pipeline_events: Vec::new(),
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let runtime_snapshot = state.runtime_snapshot.expect("runtime snapshot");
    assert_eq!(
        runtime_snapshot
            .turn_state
            .text_by_stream_id
            .get("main")
            .map(String::as_str),
        Some("Pipeline text")
    );
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0]
            .primary_text_snapshot
            .as_deref(),
        Some("Pipeline text")
    );
}

#[test]
fn ui_intent_pipeline_apply_events_syncs_runtime_and_store_snapshot() {
    let response = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "pipeline_apply_events".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: vec![
            MainChatEvent {
                id: "pipeline-1".to_string(),
                conversation_id: "conv-1".to_string(),
                assistant_message_id: "msg-1".to_string(),
                turn_id: "turn-1".to_string(),
                sequence: 2,
                source: "pipeline".to_string(),
                kind: MainChatEventKind::TextDelta,
                payload: [
                    ("stream_id".to_string(), "main".to_string()),
                    ("delta".to_string(), "Pipeline ".to_string()),
                ]
                .into_iter()
                .collect(),
                timestamp: 42.0,
            },
            MainChatEvent {
                id: "pipeline-2".to_string(),
                conversation_id: "conv-1".to_string(),
                assistant_message_id: "msg-1".to_string(),
                turn_id: "turn-1".to_string(),
                sequence: 3,
                source: "pipeline".to_string(),
                kind: MainChatEventKind::TextDelta,
                payload: [
                    ("stream_id".to_string(), "main".to_string()),
                    ("delta".to_string(), "batch".to_string()),
                ]
                .into_iter()
                .collect(),
                timestamp: 43.0,
            },
        ],
        payload: Default::default(),
    });
    let state = response.state.expect("state");
    let runtime_snapshot = state.runtime_snapshot.expect("runtime snapshot");
    assert_eq!(
        runtime_snapshot
            .turn_state
            .text_by_stream_id
            .get("main")
            .map(String::as_str),
        Some("Hello worldPipeline batch")
    );
    assert_eq!(
        state.store_snapshot.conversations[0].messages[0]
            .primary_text_snapshot
            .as_deref(),
        Some("Hello worldPipeline batch")
    );
}

#[test]
fn ui_intent_auto_todo_begin_record_and_finalize_emit_patches() {
    let begin = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_begin_runtime".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            ("assistant_message_id".to_string(), "msg-1".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
            ("path".to_string(), "Sources/App.swift".to_string()),
            ("immediate_label".to_string(), "Editing code".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert_eq!(begin.todo_patches.len(), 1);
    assert_eq!(
        begin.todo_patches[0].title.as_deref(),
        Some("Complete changes on App.swift")
    );
    assert!(begin.todo_patches[0].is_operational_placeholder);

    let record = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_record_operation".to_string(),
        state: begin.state.expect("state"),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(43.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            ("assistant_message_id".to_string(), "msg-1".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
            ("file".to_string(), "Tests/AppTests.swift".to_string()),
            ("immediate_label".to_string(), "Editing code".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    let record_state = record.state.expect("state");
    assert_eq!(
        record_state
            .auto_todo_runtime_state_by_message
            .get("msg-1")
            .map(|runtime| runtime.operation_count),
        Some(1)
    );
    assert_eq!(
        record.todo_patches[0].notes.as_deref(),
        Some("Auto-generated: tracking live operational activity until the agent publishes an explicit todo.")
    );
    assert!(record.todo_patches[0].is_operational_placeholder);

    let finalize = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_finalize_runtime".to_string(),
        state: record_state,
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(44.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            ("assistant_message_id".to_string(), "msg-1".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
            ("outcome".to_string(), "success".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert!(finalize
        .state
        .expect("state")
        .auto_todo_runtime_state_by_message
        .is_empty());
    assert_eq!(finalize.todo_patches.len(), 2);
    assert_eq!(finalize.todo_patches[0].status.as_deref(), Some("done"));
    assert!(finalize.todo_patches[0].is_operational_placeholder);
}

#[test]
fn ui_intent_auto_todo_discard_clears_runtime_state() {
    let begin = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_begin_runtime".to_string(),
        state: base_ui_state(),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(42.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            ("assistant_message_id".to_string(), "msg-1".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
            ("command".to_string(), "rg TODO Sources/".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    let discard = handle_ui_intent(MainChatUiIntentRequest {
        schema_version: 1,
        intent: "auto_todo_discard_runtime".to_string(),
        state: begin.state.expect("state"),
        conversation_id: Some("conv-1".to_string()),
        turn_id: None,
        artifact_id: None,
        text: None,
        timestamp: Some(43.0),
        pipeline_event: None,
        pipeline_events: Vec::new(),
        payload: [
            ("assistant_message_id".to_string(), "msg-1".to_string()),
            ("provider_id".to_string(), "codex-cli".to_string()),
        ]
        .into_iter()
        .collect(),
    });
    assert!(discard
        .state
        .expect("state")
        .auto_todo_runtime_state_by_message
        .is_empty());
    assert_eq!(discard.todo_patches.len(), 2);
    assert_eq!(
        discard.todo_patches[0].mutation,
        Some(app_core_protocol::main_chat_ui::MainChatUiTodoMutation::RemoveTodo)
    );
    assert!(discard.todo_patches[0].is_operational_placeholder);
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
                text_by_stream_id: [("main".to_string(), "Hello world".to_string())]
                    .into_iter()
                    .collect(),
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
        auto_todo_runtime_state_by_message: Default::default(),
    }
}

fn stale_runtime_target_ui_state() -> MainChatUiState {
    MainChatUiState {
        store_snapshot: MainChatStoreSnapshot {
            conversations: vec![MainChatStoreConversationSnapshot {
                id: "conv-1".to_string(),
                thread_root_conversation_id: "conv-1".to_string(),
                title: "Main".to_string(),
                messages: vec![
                    MainChatStoreMessageSnapshot {
                        id: "msg-old".to_string(),
                        role: "assistant".to_string(),
                        content: "Older answer".to_string(),
                        primary_text_snapshot: Some("Older answer".to_string()),
                        blocks: None,
                        turn_metadata: None,
                        is_streaming: false,
                        image_paths: None,
                        attachments: None,
                        plan_attachment: None,
                        reasoning_text: None,
                        subagent_cards: None,
                    },
                    MainChatStoreMessageSnapshot {
                        id: "msg-current".to_string(),
                        role: "assistant".to_string(),
                        content: String::new(),
                        primary_text_snapshot: Some(String::new()),
                        blocks: None,
                        turn_metadata: None,
                        is_streaming: true,
                        image_paths: None,
                        attachments: None,
                        plan_attachment: None,
                        reasoning_text: None,
                        subagent_cards: None,
                    },
                ],
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
                assistant_message_id: "msg-missing".to_string(),
                turn_id: "turn-2".to_string(),
                status: "streaming".to_string(),
                is_streaming: true,
                ordered_text_stream_ids: vec!["main".to_string()],
                text_by_stream_id: [("main".to_string(), "New answer".to_string())]
                    .into_iter()
                    .collect(),
                artifacts: vec![],
                ..Default::default()
            },
            mode: None,
            direct_stream: None,
            plan: None,
            output: None,
        }),
        task_runtime_state: None,
        selected_conversation_id: Some("conv-1".to_string()),
        draft_text: String::new(),
        plan_panel_visible: false,
        follow_live: true,
        collapsed_artifact_ids_by_turn: Default::default(),
        auto_todo_runtime_state_by_message: Default::default(),
    }
}
