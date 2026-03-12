use super::common::{encode_raw, with_raw_json_input};
use crate::review_mcp::{
    build_review_index, claim_commands, enqueue_bughunter_command, enqueue_review_command,
    handle_bughunter_tool, handle_review_tool, handle_security_tool, heartbeat_command,
    mark_command,
};
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn review_core_mcp_handle_tool(input: *const c_char) -> *mut c_char {
    tool_request_call(input, handle_review_tool)
}

#[no_mangle]
pub extern "C" fn review_core_security_handle_tool(input: *const c_char) -> *mut c_char {
    tool_request_call(input, handle_security_tool)
}

#[no_mangle]
pub extern "C" fn review_core_bughunter_handle_tool(input: *const c_char) -> *mut c_char {
    tool_request_call(input, handle_bughunter_tool)
}

#[no_mangle]
pub extern "C" fn review_core_mcp_enqueue_command(input: *const c_char) -> *mut c_char {
    queue_request_call(input, |request| match request.queue_kind.as_str() {
        "review" => enqueue_review_command(request),
        "bughunter" => enqueue_bughunter_command(request),
        _ => crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(
            "unsupported_queue_kind",
            request.commands,
        ),
    })
}

#[no_mangle]
pub extern "C" fn review_core_mcp_claim_commands(input: *const c_char) -> *mut c_char {
    queue_request_call(input, claim_commands)
}

#[no_mangle]
pub extern "C" fn review_core_mcp_mark_command(input: *const c_char) -> *mut c_char {
    queue_request_call(input, mark_command)
}

#[no_mangle]
pub extern "C" fn review_core_mcp_command_heartbeat(input: *const c_char) -> *mut c_char {
    queue_request_call(input, heartbeat_command)
}

#[no_mangle]
pub extern "C" fn review_core_mcp_read_index(input: *const c_char) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPIndexRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(_) => return empty_index_payload(),
        };
        if request.schema_version != 1 {
            return empty_index_payload();
        }
        encode_raw(&build_review_index(request))
    })
}

fn tool_request_call(
    input: *const c_char,
    handler: fn(crate::review_mcp::models::ReviewMCPToolRequest) -> crate::review_mcp::models::ReviewMCPToolResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPToolRequest = match serde_json::from_str(raw) {
            Ok(request) => request,
            Err(err) => {
                return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err(
                    format!("decode_failed: {}", err),
                ));
            }
        };
        if request.schema_version != 1 {
            return encode_raw(&crate::review_mcp::models::ReviewMCPToolResponse::err(
                "unsupported_schema",
            ));
        }
        encode_raw(&handler(request))
    })
}

fn queue_request_call(
    input: *const c_char,
    handler: fn(
        crate::review_mcp::models::ReviewMCPCommandQueueRequest,
    ) -> crate::review_mcp::models::ReviewMCPCommandQueueResponse,
) -> *mut c_char {
    with_raw_json_input(input, |raw| {
        let request: crate::review_mcp::models::ReviewMCPCommandQueueRequest =
            match serde_json::from_str(raw) {
                Ok(request) => request,
                Err(err) => {
                    return encode_raw(
                        &crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(
                            format!("decode_failed: {}", err),
                            Vec::new(),
                        ),
                    );
                }
            };
        if request.schema_version != 1 {
            return encode_raw(
                &crate::review_mcp::models::ReviewMCPCommandQueueResponse::err(
                    "unsupported_schema",
                    request.commands,
                ),
            );
        }
        encode_raw(&handler(request))
    })
}

fn empty_index_payload() -> String {
    "{\"schemaVersion\":1,\"latestSessionId\":null,\"latestSessionIdByConversation\":{},\"sessions\":[]}".to_string()
}
