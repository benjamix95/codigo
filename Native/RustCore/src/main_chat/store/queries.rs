use super::messages::normalize_message;
use app_core_protocol::main_chat_store::{MainChatStoreResponse, MainChatStoreSnapshot};

pub fn load_snapshot(snapshot: MainChatStoreSnapshot) -> MainChatStoreResponse {
    MainChatStoreResponse::success(normalize_snapshot(snapshot))
}

pub fn replace_snapshot(snapshot: MainChatStoreSnapshot) -> MainChatStoreResponse {
    MainChatStoreResponse::success(normalize_snapshot(snapshot))
}

fn normalize_snapshot(mut snapshot: MainChatStoreSnapshot) -> MainChatStoreSnapshot {
    for conversation in snapshot.conversations.iter_mut() {
        for message in conversation.messages.iter_mut() {
            normalize_message(message);
        }
    }
    snapshot
}
