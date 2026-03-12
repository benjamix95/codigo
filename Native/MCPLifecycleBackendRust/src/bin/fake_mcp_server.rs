use app_core_protocol::jsonrpc::{JsonRpcInbound, JsonRpcResponse};
use app_core_protocol::mcp::{
    CallToolResult, InitializeResult, ListToolsResult, MCP_LATEST_PROTOCOL_VERSION, ServerCapabilities,
    ServerInfo, ToolCallParams, ToolDefinition, ToolAnnotations, ToolsCapability,
};
use serde_json::{json, Value};
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;

fn main() {
    if let Err(error) = run() {
        eprintln!("fake-mcp-server failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let boot_count = bump_boot_count()?;
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let inbound: JsonRpcInbound = serde_json::from_str(&line).map_err(|error| error.to_string())?;
        match inbound {
            JsonRpcInbound::Notification(_) => continue,
            JsonRpcInbound::Request(request) => match request.method.as_str() {
                "initialize" => {
                    let result = InitializeResult {
                        protocol_version: MCP_LATEST_PROTOCOL_VERSION.to_string(),
                        capabilities: ServerCapabilities {
                            tools: Some(ToolsCapability { list_changed: Some(false) }),
                        },
                        server_info: ServerInfo {
                            name: "fake-mcp-server".to_string(),
                            version: "1.0.0".to_string(),
                            title: Some("Fake MCP Server".to_string()),
                        },
                        instructions: None,
                    };
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                "ping" => write_line(&mut stdout, &JsonRpcResponse::ok(request.id, json!({})))?,
                "tools/list" => {
                    let result = ListToolsResult {
                        tools: vec![
                            tool("echo", "Echo input message", json_schema("message")),
                            tool("fail", "Return an MCP isError response", json_schema("message")),
                            tool("boot_count", "Return server boot count", json!({"type":"object","properties":{}})),
                            tool("cwd", "Return current working directory", json!({"type":"object","properties":{}})),
                            tool("env_value", "Return MCP_FAKE_VALUE env variable", json!({"type":"object","properties":{}})),
                        ],
                        next_cursor: None,
                    };
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                "tools/call" => {
                    let params: ToolCallParams = serde_json::from_value(
                        request.params.unwrap_or_else(|| json!({})),
                    )
                    .map_err(|error| error.to_string())?;
                    let result = handle_tool(params, boot_count)?;
                    write_line(&mut stdout, &JsonRpcResponse::ok(request.id, result))?;
                }
                _ => write_line(&mut stdout, &JsonRpcResponse::ok(request.id, json!({})))?,
            },
        }
    }
    Ok(())
}

fn handle_tool(params: ToolCallParams, boot_count: u64) -> Result<CallToolResult, String> {
    let arguments = params.arguments.unwrap_or_default();
    let message = arguments
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or_default();

    let result = match params.name.as_str() {
        "echo" => CallToolResult::text(message),
        "fail" => CallToolResult::error(message),
        "boot_count" => CallToolResult::text(boot_count.to_string()),
        "cwd" => {
            let cwd = std::env::current_dir().map_err(|error| error.to_string())?;
            CallToolResult::text(cwd.display().to_string())
        }
        "env_value" => {
            let value = std::env::var("MCP_FAKE_VALUE").unwrap_or_else(|_| "missing".to_string());
            CallToolResult::text(value)
        }
        _ => CallToolResult::error(format!("unknown tool: {}", params.name)),
    };
    Ok(result)
}

fn tool(name: &str, description: &str, schema: Value) -> ToolDefinition {
    ToolDefinition {
        name: name.to_string(),
        title: None,
        description: Some(description.to_string()),
        input_schema: schema,
        annotations: Some(ToolAnnotations {
            title: None,
            read_only_hint: Some(true),
            destructive_hint: Some(false),
            idempotent_hint: Some(true),
            open_world_hint: Some(false),
        }),
    }
}

fn json_schema(property: &str) -> Value {
    json!({
        "type": "object",
        "properties": {
            property: { "type": "string" }
        }
    })
}

fn bump_boot_count() -> Result<u64, String> {
    let Some(path) = std::env::args().nth(1).map(PathBuf::from) else {
        return Ok(1);
    };
    let current = fs::read_to_string(&path)
        .ok()
        .and_then(|text| text.trim().parse::<u64>().ok())
        .unwrap_or(0);
    let next = current + 1;
    fs::write(&path, next.to_string()).map_err(|error| error.to_string())?;
    Ok(next)
}

fn write_line<T: serde::Serialize>(stdout: &mut io::Stdout, payload: &T) -> Result<(), String> {
    let encoded = serde_json::to_string(payload).map_err(|error| error.to_string())?;
    stdout
        .write_all(encoded.as_bytes())
        .and_then(|_| stdout.write_all(b"\n"))
        .and_then(|_| stdout.flush())
        .map_err(|error| error.to_string())
}
