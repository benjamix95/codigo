use app_core_protocol::main_chat_store::{MainChatStoreResponse, MainChatStoreSnapshot};

pub fn load_snapshot(snapshot: MainChatStoreSnapshot) -> MainChatStoreResponse {
    MainChatStoreResponse::success(snapshot)
}

pub fn replace_snapshot(snapshot: MainChatStoreSnapshot) -> MainChatStoreResponse {
    MainChatStoreResponse::success(snapshot)
}
