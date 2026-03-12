use crate::error::BackendError;
use crate::protocol::{ServerConfig, ToolDescriptor};
use app_core_protocol::mcp::{
    CallToolResult, InitializeResult, ListToolsResult, ToolContent,
};
use serde_json::{Map, Value};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

pub struct McpProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next_id: u64,
}

impl McpProcess {
    pub fn spawn(server: &ServerConfig) -> Result<Self, BackendError> {
        server.validate().map_err(BackendError::invalid)?;

        let mut command = Command::new(&server.command);
        command.args(&server.args);
        if let Some(cwd) = &server.cwd {
            command.current_dir(cwd);
        }
        if !server.env.is_empty() {
            command.envs(server.env.clone());
        }
        command.stdin(Stdio::piped());
        command.stdout(Stdio::piped());
        command.stderr(Stdio::null());

        let mut child = command.spawn()?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| BackendError::io("failed to open child stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| BackendError::io("failed to open child stdout"))?;

        let mut process = Self {
            child,
            stdin,
            stdout: BufReader::new(stdout),
            next_id: 1,
        };
        process.initialize()?;
        Ok(process)
    }

    pub fn is_running(&mut self) -> Result<bool, BackendError> {
        Ok(self.child.try_wait()?.is_none())
    }

    pub fn ping(&mut self) -> Result<(), BackendError> {
        let _ = self.send_request("ping", Value::Object(Map::new()))?;
        Ok(())
    }

    pub fn list_tools(
        &mut self,
        server_id: &str,
        server_name: &str,
    ) -> Result<Vec<ToolDescriptor>, BackendError> {
        let response = self.send_request("tools/list", Value::Object(Map::new()))?;
        let result: ListToolsResult = serde_json::from_value(response)?;
        result
            .tools
            .into_iter()
            .map(|tool| {
                let schema = serde_json::to_string(&tool.input_schema)?;
                Ok(ToolDescriptor {
                    name: tool.name,
                    description: tool.description.unwrap_or_default(),
                    schema,
                    server_id: server_id.to_string(),
                    server_name: server_name.to_string(),
                })
            })
            .collect::<Result<Vec<_>, serde_json::Error>>()
            .map_err(BackendError::from)
    }

    pub fn call_tool(
        &mut self,
        tool_name: &str,
        arguments: Map<String, Value>,
    ) -> Result<CallToolResult, BackendError> {
        let params = serde_json::json!({
            "name": tool_name,
            "arguments": arguments,
        });
        let response = self.send_request("tools/call", params)?;
        serde_json::from_value(response).map_err(BackendError::from)
    }

    pub fn shutdown(&mut self) -> Result<(), BackendError> {
        if self.child.try_wait()?.is_none() {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
        Ok(())
    }

    fn initialize(&mut self) -> Result<(), BackendError> {
        let params = serde_json::json!({
            "protocolVersion": "2025-11-25",
            "capabilities": { "tools": {} },
            "clientInfo": { "name": "mcp-lifecycle-backend-rust", "version": "0.1.0" }
        });
        let response = self.send_request("initialize", params)?;
        let _: InitializeResult = serde_json::from_value(response)?;
        self.send_notification("notifications/initialized", Value::Object(Map::new()))
    }

    fn send_notification(&mut self, method: &str, params: Value) -> Result<(), BackendError> {
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        });
        self.write_line(&payload)
    }

    fn send_request(&mut self, method: &str, params: Value) -> Result<Value, BackendError> {
        let id = self.next_id;
        self.next_id += 1;
        let payload = serde_json::json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        self.write_line(&payload)?;
        self.read_response(id)
    }

    fn write_line(&mut self, payload: &Value) -> Result<(), BackendError> {
        let encoded = serde_json::to_string(payload)?;
        self.stdin.write_all(encoded.as_bytes())?;
        self.stdin.write_all(b"\n")?;
        self.stdin.flush()?;
        Ok(())
    }

    fn read_response(&mut self, expected_id: u64) -> Result<Value, BackendError> {
        let mut line = String::new();
        loop {
            line.clear();
            let read = self.stdout.read_line(&mut line)?;
            if read == 0 {
                return Err(BackendError::protocol("MCP server closed stdout"));
            }
            if line.trim().is_empty() {
                continue;
            }
            let value: Value = serde_json::from_str(line.trim())?;
            if value.get("method").is_some() && value.get("id").is_none() {
                continue;
            }
            if value.get("id").and_then(Value::as_u64) != Some(expected_id) {
                continue;
            }
            if let Some(error) = value.get("error") {
                return Err(BackendError::protocol(error.to_string()));
            }
            return value
                .get("result")
                .cloned()
                .ok_or_else(|| BackendError::protocol("missing JSON-RPC result"));
        }
    }
}

pub fn flatten_tool_content(result: &CallToolResult) -> String {
    result
        .content
        .iter()
        .map(|item| match item {
            ToolContent::Text { text } => text.clone(),
        })
        .collect::<Vec<_>>()
        .join("\n")
}
