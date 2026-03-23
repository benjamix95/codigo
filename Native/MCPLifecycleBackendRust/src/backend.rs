use crate::error::BackendError;
use crate::mcp_process::{flatten_tool_content, McpProcess};
use crate::protocol::{
    CallToolRequest, HealthRequest, ListServersRequest, ListToolsRequest, ListedServer,
    ResponseEnvelope, ServerActionRequest, ServerConfig,
};
use crate::state::{ManagedProcess, ManagedServer, ServerStatus};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

pub struct Backend {
    servers: BTreeMap<String, ManagedServer>,
    processes: BTreeMap<String, ManagedProcess>,
}

impl Backend {
    pub fn new() -> Self {
        Self {
            servers: BTreeMap::new(),
            processes: BTreeMap::new(),
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
        let tools = self.with_process_for_server(&server_id, "list_tools", |process, config| {
            process.list_tools(&config.id, &config.name)
        })?;
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
        let config = self.managed_server(&server_id)?.config.clone();
        let result = self.with_process_for_server(&server_id, "call_tool", |process, _| {
            process.call_tool(&request.tool_name, request.arguments)
        })?;
        Ok(json!({
            "serverId": config.id,
            "serverName": config.name,
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
        let config = self.managed_server(&server_id)?.config.clone();
        let process_key = self.managed_server(&server_id)?.process_key.clone();
        self.stop_process_for_key(&process_key, "reconnect")?;
        self.start_process_for_server(&server_id, "reconnect")?;
        Ok(json!({
            "serverId": config.id,
            "serverName": config.name,
            "status": ServerStatus::Ready.as_str(),
        }))
    }

    fn restart_server(&mut self, payload: Value) -> Result<Value, BackendError> {
        self.reconnect(payload)
    }

    fn shutdown_all(&mut self) -> Result<Value, BackendError> {
        let process_keys = self.processes.keys().cloned().collect::<Vec<_>>();
        let stopped = process_keys.len() as u64;
        for process_key in process_keys {
            self.stop_process_for_key(&process_key, "shutdown_all")?;
        }
        for managed in self.servers.values_mut() {
            managed.status = ServerStatus::Stopped;
            managed.last_error = None;
            managed.touch("shutdown_all");
        }
        Ok(json!({ "stopped": stopped }))
    }

    fn upsert_servers(&mut self, servers: Vec<ServerConfig>) -> Result<(), BackendError> {
        for server in servers {
            server.validate().map_err(BackendError::invalid)?;
            let process_key = server.process_key();
            self.servers
                .entry(server.id.clone())
                .and_modify(|managed| {
                    managed.config = server.clone();
                    managed.process_key = process_key.clone();
                    managed.touch("upsert");
                })
                .or_insert_with(|| ManagedServer::new(server));
        }
        self.reap_orphan_processes()?;
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

    pub(crate) fn with_process_for_server<T, F>(
        &mut self,
        server_id: &str,
        reason: &str,
        f: F,
    ) -> Result<T, BackendError>
    where
        F: FnOnce(&mut McpProcess, &ServerConfig) -> Result<T, BackendError>,
    {
        let (config, process_key) = self.ensure_connected(server_id, reason)?;
        let result = {
            let managed_process = self.managed_process_mut(&process_key)?;
            match f(&mut managed_process.process, &config) {
                Ok(result) => {
                    managed_process.last_error = None;
                    managed_process.touch(reason);
                    Ok(result)
                }
                Err(error) => {
                    managed_process.last_error = Some(error.to_string());
                    managed_process.touch(reason);
                    Err(error)
                }
            }
        };

        match result {
            Ok(result) => {
                self.update_servers_for_process_key(&process_key, ServerStatus::Ready, None, reason);
                Ok(result)
            }
            Err(error) => {
                self.update_servers_for_process_key(
                    &process_key,
                    ServerStatus::Failed,
                    Some(error.to_string()),
                    reason,
                );
                Err(error)
            }
        }
    }

    pub(crate) fn managed_server(&self, server_id: &str) -> Result<&ManagedServer, BackendError> {
        self.servers
            .get(server_id)
            .ok_or_else(|| BackendError::not_found(format!("unknown serverId: {server_id}")))
    }

    fn managed_process_mut(&mut self, process_key: &str) -> Result<&mut ManagedProcess, BackendError> {
        self.processes
            .get_mut(process_key)
            .ok_or_else(|| BackendError::protocol(format!("missing managed process for key: {process_key}")))
    }

    fn ensure_connected(
        &mut self,
        server_id: &str,
        reason: &str,
    ) -> Result<(ServerConfig, String), BackendError> {
        let (config, process_key) = {
            let managed = self.managed_server(server_id)?;
            (managed.config.clone(), managed.process_key.clone())
        };

        let needs_restart = match self.processes.get_mut(&process_key) {
            Some(managed_process) => !managed_process.process.is_running()?,
            None => true,
        };

        if needs_restart {
            self.stop_process_for_key(&process_key, "restart_stale_process").ok();
            self.start_process(&config, &process_key, reason)?;
        } else if let Some(managed_process) = self.processes.get_mut(&process_key) {
            managed_process.touch(reason);
        }

        self.update_servers_for_process_key(&process_key, ServerStatus::Ready, None, reason);
        Ok((config, process_key))
    }

    fn refresh_status(&mut self, server_id: &str) -> Result<String, BackendError> {
        let process_key = self.managed_server(server_id)?.process_key.clone();
        let status = if let Some(managed_process) = self.processes.get_mut(&process_key) {
            if managed_process.process.is_running()? {
                match managed_process.process.ping() {
                    Ok(()) => {
                        managed_process.last_error = None;
                        managed_process.touch("health");
                        ServerStatus::Ready
                    }
                    Err(error) => {
                        managed_process.last_error = Some(error.to_string());
                        managed_process.touch("health_ping_failed");
                        ServerStatus::Failed
                    }
                }
            } else {
                self.processes.remove(&process_key);
                ServerStatus::Stopped
            }
        } else {
            self.managed_server(server_id)?.status
        };

        let error = match status {
            ServerStatus::Failed => self
                .processes
                .get(&process_key)
                .and_then(|managed_process| managed_process.last_error.clone()),
            _ => None,
        };
        self.update_servers_for_process_key(&process_key, status, error, "health");
        Ok(status.as_str().to_string())
    }

    fn start_process(
        &mut self,
        config: &ServerConfig,
        process_key: &str,
        reason: &str,
    ) -> Result<(), BackendError> {
        match McpProcess::spawn(config) {
            Ok(process) => {
                self.processes.insert(
                    process_key.to_string(),
                    ManagedProcess::new(process, reason),
                );
                self.update_servers_for_process_key(process_key, ServerStatus::Ready, None, reason);
                Ok(())
            }
            Err(error) => {
                self.update_servers_for_process_key(
                    process_key,
                    ServerStatus::Failed,
                    Some(error.to_string()),
                    reason,
                );
                Err(error)
            }
        }
    }

    fn start_process_for_server(&mut self, server_id: &str, reason: &str) -> Result<(), BackendError> {
        let managed = self.managed_server(server_id)?;
        let config = managed.config.clone();
        let process_key = managed.process_key.clone();
        self.start_process(&config, &process_key, reason)
    }

    fn stop_process_for_key(&mut self, process_key: &str, reason: &str) -> Result<(), BackendError> {
        if let Some(mut managed_process) = self.processes.remove(process_key) {
            managed_process.process.shutdown()?;
        }
        self.update_servers_for_process_key(process_key, ServerStatus::Stopped, None, reason);
        Ok(())
    }

    fn update_servers_for_process_key(
        &mut self,
        process_key: &str,
        status: ServerStatus,
        last_error: Option<String>,
        reason: &str,
    ) {
        for managed in self
            .servers
            .values_mut()
            .filter(|managed| managed.process_key == process_key)
        {
            managed.status = status;
            managed.last_error = last_error.clone();
            managed.touch(reason);
        }
    }

    fn reap_orphan_processes(&mut self) -> Result<(), BackendError> {
        let referenced = self
            .servers
            .values()
            .map(|managed| managed.process_key.clone())
            .collect::<BTreeSet<_>>();
        let orphaned = self
            .processes
            .keys()
            .filter(|process_key| !referenced.contains(*process_key))
            .cloned()
            .collect::<Vec<_>>();
        for process_key in orphaned {
            self.stop_process_for_key(&process_key, "reap_orphan")?;
        }
        Ok(())
    }
}
