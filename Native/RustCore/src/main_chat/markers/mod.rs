mod patterns;
mod sanitize;
mod tests;
mod thinking;

/// Per store/UI: strip marker operativi da testo reasoning (pub(crate) verso `main_chat::store`).
pub(crate) fn strip_coderide_markers_wire(content: &str, aggressive: bool) -> String {
    sanitize::strip_coderide_markers(content, aggressive)
}

use app_core_protocol::main_chat_markers::{MainChatMarkersRequest, MainChatMarkersResponse};

pub fn handle_request(request: MainChatMarkersRequest) -> MainChatMarkersResponse {
    if request.schema_version != 1 {
        return MainChatMarkersResponse::error("unsupported_schema", "schemaVersion must be 1");
    }

    match request.operation.as_str() {
        "strip_coderide_markers" => MainChatMarkersResponse::success(Some(
            sanitize::strip_coderide_markers(&request.text, request.aggressive.unwrap_or(true)),
        )),
        "extract_last_operational_thinking_line" => MainChatMarkersResponse::success(
            thinking::extract_last_operational_thinking_line(&request.text),
        ),
        _ => {
            MainChatMarkersResponse::error("unsupported_operation", "Unsupported markers operation")
        }
    }
}
