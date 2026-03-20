use super::{checkpoints, conversations, messages, plans};
use app_core_protocol::main_chat_store::{MainChatStoreActionRequest, MainChatStoreResponse};

pub fn handle_action(request: MainChatStoreActionRequest) -> MainChatStoreResponse {
    if request.schema_version != 1 {
        return MainChatStoreResponse::error("unsupported_schema", "schemaVersion must be 1");
    }
    match request.action.as_str() {
        "create_conversation" => conversations::create_conversation(request.snapshot.clone(), &request),
        "delete_conversation" => {
            let Some(conversation_id) = request.conversation_id.as_deref() else {
                return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
            };
            conversations::delete_conversation(request.snapshot, conversation_id)
        }
        "append_message" => messages::append_message(request.snapshot.clone(), &request),
        "insert_message_before" => messages::insert_message_before(request.snapshot.clone(), &request),
        "replace_message" | "update_assistant_message" => {
            messages::replace_or_update_message(request.snapshot.clone(), &request)
        }
        "sync_assistant_content" => messages::sync_assistant_content(request.snapshot.clone(), &request),
        "sync_assistant_pipeline_state" => {
            messages::sync_assistant_pipeline_state(request.snapshot.clone(), &request)
        }
        "save_reasoning" => messages::save_reasoning(request.snapshot.clone(), &request),
        "save_subagent_cards_to_last_assistant" => {
            messages::save_subagent_cards_to_last_assistant(request.snapshot.clone(), &request)
        }
        "set_streaming_state" => messages::set_streaming_state(request.snapshot.clone(), &request),
        "remove_trailing_empty_assistant_messages" => {
            messages::remove_trailing_empty_assistant_messages(request.snapshot.clone(), &request)
        }
        "remove_assistant_message_if_empty" => {
            messages::remove_assistant_message_if_empty(request.snapshot.clone(), &request)
        }
        "remove_message" => messages::remove_message(request.snapshot.clone(), &request),
        "set_plan_board" => plans::set_plan_board(request.snapshot.clone(), &request),
        "remove_plan_board" => {
            let Some(conversation_id) = request.conversation_id.as_deref() else {
                return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
            };
            plans::remove_plan_board(request.snapshot.clone(), conversation_id)
        }
        "attach_plan_to_message" => plans::attach_plan_to_message(request.snapshot.clone(), &request),
        "create_checkpoint" => checkpoints::create_checkpoint(request.snapshot.clone(), &request),
        "rewind_to_checkpoint" => {
            let Some(conversation_id) = request.conversation_id.as_deref() else {
                return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
            };
            let Some(checkpoint_id) = request.checkpoint_id.as_deref() else {
                return MainChatStoreResponse::error("missing_checkpoint_id", "checkpointId is required");
            };
            checkpoints::rewind_to_checkpoint(request.snapshot.clone(), checkpoint_id, conversation_id)
        }
        "rewind_to_message_count" => {
            let Some(conversation_id) = request.conversation_id.as_deref() else {
                return MainChatStoreResponse::error("missing_conversation_id", "conversationId is required");
            };
            let Some(message_count) = request.message_count else {
                return MainChatStoreResponse::error("missing_message_count", "messageCount is required");
            };
            checkpoints::rewind_to_message_count(request.snapshot.clone(), message_count, conversation_id)
        }
        "set_archived" | "set_pinned" | "set_favorite" | "set_title" | "set_mode"
        | "set_preferred_provider" | "set_context" | "set_context_folder"
        | "set_workspace" | "set_ad_hoc_paths" | "set_last_input_tokens"
        | "set_context_memory_summary" => conversations::update_conversation_preferences(
            request.snapshot.clone(),
            &request,
        ),
        _ => MainChatStoreResponse::error("unsupported_action", "Unsupported store action"),
    }
}
