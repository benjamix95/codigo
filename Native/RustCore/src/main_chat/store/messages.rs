mod append;
mod assistant;
mod cleanup;
mod helpers;

pub use append::{append_message, insert_message_before};
pub use assistant::{
    remove_assistant_message_if_empty, replace_or_update_message, save_reasoning,
    save_subagent_cards_to_last_assistant, set_streaming_state, sync_assistant_content,
    sync_assistant_pipeline_state,
};
pub use cleanup::{remove_message, remove_trailing_empty_assistant_messages};
