use crate::backend::Backend;
use crate::error::BackendError;
use crate::protocol::{PromptRequest, ResourceRequest};
use serde_json::{json, Value};

impl Backend {
    pub(crate) fn list_resources(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let resources = self.with_process_for_server(&server_id, "list_resources", |process, config| {
            process.list_resources(&config.id, &config.name)
        })?;
        Ok(json!({ "resources": resources }))
    }

    pub(crate) fn read_resource(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        if request.uri.trim().is_empty() {
            return Err(BackendError::invalid("uri is required"));
        }
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let contents = self.with_process_for_server(&server_id, "read_resource", |process, _| {
            process.read_resource(&request.uri)
        })?;
        Ok(json!({ "contents": contents }))
    }

    pub(crate) fn subscribe_resource(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        if request.uri.trim().is_empty() {
            return Err(BackendError::invalid("uri is required"));
        }
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        self.with_process_for_server(&server_id, "subscribe_resource", |process, _| {
            process.subscribe_resource(&request.uri)
        })?;
        Ok(json!({ "uri": request.uri }))
    }

    pub(crate) fn unsubscribe_resource(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        if request.uri.trim().is_empty() {
            return Err(BackendError::invalid("uri is required"));
        }
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        self.with_process_for_server(&server_id, "unsubscribe_resource", |process, _| {
            process.unsubscribe_resource(&request.uri)
        })?;
        Ok(json!({ "uri": request.uri }))
    }

    pub(crate) fn list_resource_templates(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let templates = self.with_process_for_server(&server_id, "list_resource_templates", |process, config| {
            process.list_resource_templates(&config.id, &config.name)
        })?;
        Ok(json!({ "templates": templates }))
    }

    pub(crate) fn list_prompts(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: PromptRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let prompts = self.with_process_for_server(&server_id, "list_prompts", |process, config| {
            process.list_prompts(&config.id, &config.name)
        })?;
        Ok(json!({ "prompts": prompts }))
    }

    pub(crate) fn get_prompt(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: PromptRequest = serde_json::from_value(payload)?;
        if request.name.trim().is_empty() {
            return Err(BackendError::invalid("name is required"));
        }
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let result = self.with_process_for_server(&server_id, "get_prompt", |process, _| {
            process.get_prompt(&request.name, request.arguments)
        })?;
        Ok(json!({
            "description": result.description,
            "messages": result.messages,
        }))
    }
}
