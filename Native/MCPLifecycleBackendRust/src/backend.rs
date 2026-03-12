use crate::error::BackendError;
use crate::mcp_process::{flatten_tool_content, McpProcess};
use crate::protocol::{
    CallToolRequest, HealthRequest, ListServersRequest, ListToolsRequest, ListedServer,
    ResponseEnvelope, ServerActionRequest, ServerConfig,
};
use crate::state::{ManagedServer, ServerStatus};
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;

pub struct Backend {
    servers: BTreeMap<String, ManagedServer>,
}

impl Backend {
    pub fn new() -> Self {
        Self {
            servers: BTreeMap::new(),
        }
    }

    pub fn handle(&mut self, id: String, op: &str, payload: Value) -> ResponseEnvelope {
        let result = match op {
            "list_servers" => self.list_servers(payload),
            "health" => self.health(payload),
            "list_tools" => self.list_tools(payload),
            "describe_tool" => self.describe_tool(payload),
            "call_tool" => self.call_tool(payload),
            "call_tools_batch" => self.call_tools_batch(payload),
            "list_resources" => self.list_resources(payload),
            "read_resource" => self.read_resource(payload),
            "subscribe_resource" => self.subscribe_resource(payload),
            "unsubscribe_resource" => self.unsubscribe_resource(payload),
            "list_resource_templates" => self.list_resource_templates(payload),
            "list_prompts" => self.list_prompts(payload),
            "get_prompt" => self.get_prompt(payload),
            "reconnect" => self.reconnect(payload),
            "restart_server" => self.restart_server(payload),
            "shutdown_all" => self.shutdown_all(),
            _ => Err(BackendError::invalid(format!("unsupported op: {op}"))),
        };

        match result {
            Ok(payload) => ResponseEnvelope::ok(id, payload),
            Err(error) => ResponseEnvelope::err(id, error.to_string()),
        }
    }

    fn list_servers(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ListServersRequest = serde_json::from_value(payload)?;
        self.upsert_servers(request.servers)?;
        let servers = self
            .servers
            .values()
            .map(|server| ListedServer {
                id: server.config.id.clone(),
                name: server.config.name.clone(),
                source: server.config.source.clone(),
                status: server.status.as_str().to_string(),
            })
            .collect::<Vec<_>>();
        Ok(json!({ "servers": servers }))
    }

    fn health(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: HealthRequest = serde_json::from_value(payload)?;
        self.upsert_servers(request.servers)?;
        let ids = self.servers.keys().cloned().collect::<Vec<_>>();
        let mut states = Map::new();
        for server_id in ids {
            let status = self.refresh_status(&server_id)?;
            states.insert(server_id, Value::String(status));
        }
        Ok(Value::Object(Map::from_iter([(
            "states".to_string(),
            Value::Object(states),
        )])))
    }

    fn list_tools(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ListToolsRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let tools = {
            let managed = self.ensure_connected(&server_id)?;
            let descriptors = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .list_tools(&managed.config.id, &managed.config.name)?;
            managed.status = ServerStatus::Ready;
            descriptors
        };
        Ok(json!({ "tools": tools }))
    }

    fn call_tool(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: CallToolRequest = serde_json::from_value(payload)?;
        if request.tool_name.trim().is_empty() {
            return Err(BackendError::invalid("toolName is required"));
        }
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let managed = self.ensure_connected(&server_id)?;
        let result = managed
            .process
            .as_mut()
            .ok_or_else(|| BackendError::protocol("missing MCP process"))?
            .call_tool(&request.tool_name, request.arguments)?;
        managed.status = ServerStatus::Ready;
        Ok(json!({
            "serverId": managed.config.id,
            "serverName": managed.config.name,
            "content": flatten_tool_content(&result),
            "isError": result.is_error.unwrap_or(false),
        }))
    }

    fn reconnect(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ServerActionRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        {
            let managed = self.managed_server_mut(&server_id)?;
            Self::stop_process(managed)?;
        }
        {
            let managed = self.managed_server_mut(&server_id)?;
            Self::start_process(managed)?;
        }
        let managed = self.managed_server_mut(&server_id)?;
        Ok(json!({
            "serverId": managed.config.id,
            "serverName": managed.config.name,
            "status": managed.status.as_str(),
        }))
    }

    fn restart_server(&mut self, payload: Value) -> Result<Value, BackendError> {
        self.reconnect(payload)
    }

    fn shutdown_all(&mut self) -> Result<Value, BackendError> {
        let ids = self.servers.keys().cloned().collect::<Vec<_>>();
        let mut stopped = 0_u64;
        for server_id in ids {
            let managed = self.managed_server_mut(&server_id)?;
            if managed.process.is_some() {
                Self::stop_process(managed)?;
                stopped += 1;
            } else {
                managed.status = ServerStatus::Stopped;
            }
        }
        Ok(json!({ "stopped": stopped }))
    }

    fn upsert_servers(&mut self, servers: Vec<ServerConfig>) -> Result<(), BackendError> {
        for server in servers {
            server.validate().map_err(BackendError::invalid)?;
            self.servers
                .entry(server.id.clone())
                .and_modify(|managed| managed.config = server.clone())
                .or_insert_with(|| ManagedServer::new(server));
        }
        Ok(())
    }

    pub(crate) fn resolve_server_identity(
        &mut self,
        server_id: Option<String>,
        server_name: Option<String>,
        server: Option<ServerConfig>,
    ) -> Result<String, BackendError> {
        if let Some(server) = server {
            let id = server.id.clone();
            self.upsert_servers(vec![server])?;
            return Ok(id);
        }
        if let Some(server_id) = server_id.filter(|value| !value.trim().is_empty()) {
            if self.servers.contains_key(&server_id) {
                return Ok(server_id);
            }
            return Err(BackendError::not_found(format!("unknown serverId: {server_id}")));
        }
        if let Some(server_name) = server_name.filter(|value| !value.trim().is_empty()) {
            let mut matches = self
                .servers
                .values()
                .filter(|server| server.config.name == server_name)
                .map(|server| server.config.id.clone())
                .collect::<Vec<_>>();
            if matches.len() == 1 {
                return Ok(matches.remove(0));
            }
            if matches.is_empty() {
                return Err(BackendError::not_found(format!("unknown serverName: {server_name}")));
            }
            return Err(BackendError::invalid(format!(
                "ambiguous serverName: {server_name}"
            )));
        }
        Err(BackendError::invalid(
            "serverId or server is required for this op",
        ))
    }

    pub(crate) fn ensure_connected(&mut self, server_id: &str) -> Result<&mut ManagedServer, BackendError> {
        let needs_restart = match self.managed_server_mut(server_id)?.process.as_mut() {
            Some(process) => !process.is_running()?,
            None => true,
        };
        if needs_restart {
            let managed = self.managed_server_mut(server_id)?;
            Self::start_process(managed)?;
        }
        self.managed_server_mut(server_id)
    }

    fn refresh_status(&mut self, server_id: &str) -> Result<String, BackendError> {
        let managed = self.managed_server_mut(server_id)?;
        let status = if let Some(process) = managed.process.as_mut() {
            if process.is_running()? {
                match process.ping() {
                    Ok(()) => {
                        managed.status = ServerStatus::Ready;
                        ServerStatus::Ready
                    }
                    Err(error) => {
                        managed.status = ServerStatus::Failed;
                        managed.last_error = Some(error.to_string());
                        ServerStatus::Failed
                    }
                }
            } else {
                managed.status = ServerStatus::Stopped;
                managed.process = None;
                ServerStatus::Stopped
            }
        } else {
            managed.status
        };
        Ok(status.as_str().to_string())
    }

    fn start_process(managed: &mut ManagedServer) -> Result<(), BackendError> {
        match McpProcess::spawn(&managed.config) {
            Ok(process) => {
                managed.process = Some(process);
                managed.status = ServerStatus::Ready;
                managed.last_error = None;
                Ok(())
            }
            Err(error) => {
                managed.process = None;
                managed.status = ServerStatus::Failed;
                managed.last_error = Some(error.to_string());
                Err(error)
            }
        }
    }

    fn stop_process(managed: &mut ManagedServer) -> Result<(), BackendError> {
        if let Some(process) = managed.process.as_mut() {
            process.shutdown()?;
        }
        managed.process = None;
        managed.status = ServerStatus::Stopped;
        Ok(())
    }

    fn managed_server_mut(&mut self, server_id: &str) -> Result<&mut ManagedServer, BackendError> {
        self.servers
            .get_mut(server_id)
            .ok_or_else(|| BackendError::not_found(format!("unknown serverId: {server_id}")))
    }
}
