use crate::catalog;
use crate::handlers;
use app_core_protocol::jsonrpc::{
    JsonRpcErrorResponse, JsonRpcId, JsonRpcInbound, JsonRpcResponse,
};
use app_core_protocol::mcp::{
    CallToolResult, InitializeResult, ListToolsResult, MCP_LATEST_PROTOCOL_VERSION, ServerCapabilities,
    ServerInfo, ToolCallParams, ToolsCapability,
};
use serde_json::Value;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

pub struct ServerConfig {
    pub workspace: PathBuf,
}

pub fn run_stdio_server(config: ServerConfig) -> Result<(), String> {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let inbound: JsonRpcInbound = match serde_json::from_str(&line) {
            Ok(inbound) => inbound,
            Err(error) => {
                let response = JsonRpcErrorResponse::parse_error(
                    JsonRpcId::Number(0),
                    format!("invalid json: {error}"),
                );
                write_line(&mut stdout, &response)?;
                continue;
            }
        };
        match inbound {
            JsonRpcInbound::Notification(notification) => {
                if notification.method == "notifications/initialized" {
                    continue;
                }
            }
            JsonRpcInbound::Request(request) => match request.method.as_str() {
                "initialize" => {
                    let result = InitializeResult {
                        protocol_version: MCP_LATEST_PROTOCOL_VERSION.to_string(),
                        capabilities: ServerCapabilities {
                            tools: Some(ToolsCapability {
                                list_changed: Some(false),
                            }),
                        },
                        server_info: ServerInfo {
                            name: "coderide-tools-rust".to_string(),
                            version: "0.1.0".to_string(),
                            title: Some("CoderIDE Tools (Rust)".to_string()),
                        },
                        instructions: Some(format!(
                            "Rust MCP server for CoderIDE. Prefer native Rust tools over shell when available. Catalog version: {}. Tool count: {}.",
                            catalog::CATALOG_VERSION,
                            catalog::CATALOG_TOOL_COUNT
                        )),
                    };
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                "ping" => {
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, Value::Object(Default::default())))?;
                }
                "tools/list" => {
                    let result = ListToolsResult {
                        tools: catalog::all_tools(),
                        next_cursor: None,
                    };
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                "tools/call" => {
                    let params_value = request.params.unwrap_or(Value::Object(Default::default()));
                    let params: ToolCallParams = match serde_json::from_value(params_value) {
                        Ok(params) => params,
                        Err(error) => {
                            let response = JsonRpcErrorResponse::invalid_params(
                                request.id,
                                format!("invalid tools/call params: {error}"),
                            );
                            write_line(&mut stdout, &response)?;
                            continue;
                        }
                    };
                    let result: CallToolResult = handlers::handle_tool_call(&config.workspace, params);
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                _ => {
                    let response = JsonRpcErrorResponse::method_not_found(
                        request.id,
                        format!("unsupported method: {}", request.method),
                    );
                    write_line(&mut stdout, &response)?;
                }
            },
        }
    }
    Ok(())
}

fn write_line<T: serde::Serialize>(stdout: &mut io::Stdout, payload: &T) -> Result<(), String> {
    let encoded = serde_json::to_string(payload).map_err(|error| error.to_string())?;
    stdout
        .write_all(encoded.as_bytes())
        .and_then(|_| stdout.write_all(b"\n"))
        .and_then(|_| stdout.flush())
        .map_err(|error| error.to_string())
}
