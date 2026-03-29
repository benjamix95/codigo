use app_core_protocol::jsonrpc::JsonRpcErrorResponse;
use crate::error::BackendError;
use crate::mcp_models::{
    PromptDescriptor, PromptResultPayload, ResourceContentPayload, ResourceDescriptor,
    ResourceTemplateDescriptor,
};
use crate::protocol::{ServerConfig, ToolDescriptor};
use app_core_protocol::mcp::{CallToolResult, InitializeResult, ListToolsResult, ToolContent};
use serde_json::{Map, Value};
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStderr, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::{Arc, Mutex};

pub struct McpProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next_id: u64,
    pending_responses: Vec<Value>,
    stderr_tail: Arc<Mutex<String>>,
}

const STDERR_TAIL_MAX_CHARS: usize = 8_192;

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
        command.stderr(Stdio::piped());

        let mut child = command.spawn()?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| BackendError::io("failed to open child stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| BackendError::io("failed to open child stdout"))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| BackendError::io("failed to open child stderr"))?;
        let stderr_tail = Arc::new(Mutex::new(String::new()));
        spawn_stderr_drain(stderr, Arc::clone(&stderr_tail));

        let mut process = Self {
            child,
            stdin,
            stdout: BufReader::new(stdout),
            next_id: 1,
            pending_responses: Vec::new(),
            stderr_tail,
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

    pub fn list_resources(
        &mut self,
        server_id: &str,
        server_name: &str,
    ) -> Result<Vec<ResourceDescriptor>, BackendError> {
        let response = self.send_request("resources/list", Value::Object(Map::new()))?;
        let resources = response
            .get("resources")
            .cloned()
            .ok_or_else(|| BackendError::protocol("missing resources/list payload"))?;
        let listed = serde_json::from_value::<Vec<ResourceDescriptor>>(resources)?;
        Ok(listed
            .into_iter()
            .map(|resource| ResourceDescriptor {
                server_id: server_id.to_string(),
                server_name: server_name.to_string(),
                ..resource
            })
            .collect())
    }

    pub fn read_resource(
        &mut self,
        uri: &str,
    ) -> Result<Vec<ResourceContentPayload>, BackendError> {
        let response = self.send_request("resources/read", serde_json::json!({ "uri": uri }))?;
        let contents = response
            .get("contents")
            .cloned()
            .ok_or_else(|| BackendError::protocol("missing resources/read payload"))?;
        serde_json::from_value(contents).map_err(BackendError::from)
    }

    pub fn subscribe_resource(&mut self, uri: &str) -> Result<(), BackendError> {
        let _ = self.send_request("resources/subscribe", serde_json::json!({ "uri": uri }))?;
        Ok(())
    }

    pub fn unsubscribe_resource(&mut self, uri: &str) -> Result<(), BackendError> {
        let _ = self.send_request("resources/unsubscribe", serde_json::json!({ "uri": uri }))?;
        Ok(())
    }

    pub fn list_resource_templates(
        &mut self,
        server_id: &str,
        server_name: &str,
    ) -> Result<Vec<ResourceTemplateDescriptor>, BackendError> {
        let response = self.send_request("resources/templates/list", Value::Object(Map::new()))?;
        let templates = response
            .get("resourceTemplates")
            .or_else(|| response.get("templates"))
            .cloned()
            .ok_or_else(|| BackendError::protocol("missing resources/templates/list payload"))?;
        let listed = serde_json::from_value::<Vec<ResourceTemplateDescriptor>>(templates)?;
        Ok(listed
            .into_iter()
            .map(|template| ResourceTemplateDescriptor {
                server_id: server_id.to_string(),
                server_name: server_name.to_string(),
                ..template
            })
            .collect())
    }

    pub fn list_prompts(
        &mut self,
        server_id: &str,
        server_name: &str,
    ) -> Result<Vec<PromptDescriptor>, BackendError> {
        let response = self.send_request("prompts/list", Value::Object(Map::new()))?;
        let prompts = response
            .get("prompts")
            .cloned()
            .ok_or_else(|| BackendError::protocol("missing prompts/list payload"))?;
        let listed = serde_json::from_value::<Vec<PromptDescriptor>>(prompts)?;
        Ok(listed
            .into_iter()
            .map(|prompt| PromptDescriptor {
                server_id: server_id.to_string(),
                server_name: server_name.to_string(),
                ..prompt
            })
            .collect())
    }

    pub fn get_prompt(
        &mut self,
        name: &str,
        arguments: Map<String, Value>,
    ) -> Result<PromptResultPayload, BackendError> {
        let response = self.send_request(
            "prompts/get",
            serde_json::json!({ "name": name, "arguments": arguments }),
        )?;
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
        if let Some(index) = self
            .pending_responses
            .iter()
            .position(|value| value.get("id").and_then(Value::as_u64) == Some(expected_id))
        {
            let value = self.pending_responses.remove(index);
            return self.extract_result(value);
        }

        let mut line = String::new();
        loop {
            line.clear();
            let read = self.stdout.read_line(&mut line)?;
            if read == 0 {
                return Err(BackendError::protocol(self.with_stderr_context(
                    "MCP server closed stdout".to_string(),
                )));
            }
            if line.trim().is_empty() {
                continue;
            }
            let value: Value = serde_json::from_str(line.trim()).map_err(|error| {
                BackendError::protocol(self.with_stderr_context(error.to_string()))
            })?;
            if value.get("method").is_some() && value.get("id").is_none() {
                continue;
            }
            if value.get("method").is_some() && value.get("id").is_some() {
                self.respond_method_not_found(&value)?;
                continue;
            }
            if value.get("id").and_then(Value::as_u64) != Some(expected_id) {
                if value.get("id").is_some() {
                    self.pending_responses.push(value);
                }
                continue;
            }
            return self.extract_result(value);
        }
    }

    fn extract_result(&self, value: Value) -> Result<Value, BackendError> {
        if let Some(error) = value.get("error") {
            return Err(BackendError::protocol(self.with_stderr_context(error.to_string())));
        }
        value
            .get("result")
            .cloned()
            .ok_or_else(|| BackendError::protocol(self.with_stderr_context("missing JSON-RPC result".to_string())))
    }

    fn respond_method_not_found(&mut self, value: &Value) -> Result<(), BackendError> {
        let Some(id) = value.get("id").cloned() else {
            return Ok(());
        };
        let method = value
            .get("method")
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        let payload = serde_json::to_value(JsonRpcErrorResponse::method_not_found(
            serde_json::from_value(id).map_err(BackendError::from)?,
            format!("unsupported server-initiated method: {method}"),
        ))?;
        self.write_line(&payload)
    }

    fn with_stderr_context(&self, message: String) -> String {
        let stderr = self
            .stderr_tail
            .lock()
            .ok()
            .map(|value| value.trim().to_string())
            .unwrap_or_default();
        if stderr.is_empty() {
            message
        } else {
            format!("{message} | stderr: {stderr}")
        }
    }
}

impl Drop for McpProcess {
    fn drop(&mut self) {
        let _ = self.shutdown();
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

fn spawn_stderr_drain(stderr: ChildStderr, stderr_tail: Arc<Mutex<String>>) {
    std::thread::spawn(move || {
        let mut reader = BufReader::new(stderr);
        let mut line = String::new();
        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break,
                Ok(_) => append_stderr_tail(&stderr_tail, line.trim_end()),
                Err(_) => break,
            }
        }
    });
}

fn append_stderr_tail(stderr_tail: &Arc<Mutex<String>>, chunk: &str) {
    if chunk.is_empty() {
        return;
    }
    let Ok(mut tail) = stderr_tail.lock() else {
        return;
    };
    if !tail.is_empty() {
        tail.push('\n');
    }
    tail.push_str(chunk);
    if tail.chars().count() > STDERR_TAIL_MAX_CHARS {
        let kept = tail
            .chars()
            .rev()
            .take(STDERR_TAIL_MAX_CHARS)
            .collect::<String>()
            .chars()
            .rev()
            .collect::<String>();
        *tail = kept;
    }
}
