use super::common::{
    action, checkpoint, conversation_with_messages, empty_snapshot, message, unwrap_snapshot,
};
use crate::main_chat::store::handle_action;

#[test]
fn reducer_can_create_append_checkpoint_and_rewind() {
    let mut request = action(empty_snapshot(), "create_conversation");
    request.conversation = Some(conversation_with_messages("conv-1", "Test", Vec::new()));
    let snapshot = unwrap_snapshot(handle_action(request));
    assert_eq!(snapshot.conversations.len(), 1);

    let mut append = action(snapshot, "append_message");
    append.conversation_id = Some("conv-1".to_string());
    append.message = Some(message("msg-1", "user", "hello", false));
    let snapshot = unwrap_snapshot(handle_action(append));
    assert_eq!(snapshot.conversations[0].messages.len(), 1);

    let mut checkpoint_request = action(snapshot, "create_checkpoint");
    checkpoint_request.conversation_id = Some("conv-1".to_string());
    checkpoint_request.checkpoint = Some(checkpoint("cp-1"));
    let snapshot = unwrap_snapshot(handle_action(checkpoint_request));
    assert_eq!(snapshot.conversations[0].checkpoints.len(), 1);
    assert_eq!(snapshot.conversations[0].checkpoints[0].message_count, 1);

    let mut second_append = action(snapshot, "append_message");
    second_append.conversation_id = Some("conv-1".to_string());
    second_append.message = Some(message("msg-2", "assistant", "world", false));
    let snapshot = unwrap_snapshot(handle_action(second_append));
    assert_eq!(snapshot.conversations[0].messages.len(), 2);

    let mut rewind = action(snapshot, "rewind_to_checkpoint");
    rewind.conversation_id = Some("conv-1".to_string());
    rewind.checkpoint_id = Some("cp-1".to_string());
    let snapshot = unwrap_snapshot(handle_action(rewind));
    assert_eq!(snapshot.conversations[0].messages.len(), 1);
    assert_eq!(snapshot.conversations[0].checkpoints.len(), 0);
}
