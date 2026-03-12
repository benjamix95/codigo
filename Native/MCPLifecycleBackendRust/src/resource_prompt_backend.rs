use crate::backend::Backend;
use crate::error::BackendError;
use crate::protocol::{PromptRequest, ResourceRequest};
use crate::state::ServerStatus;
use serde_json::{json, Value};

impl Backend {
    pub(crate) fn list_resources(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let resources = {
            let managed = self.ensure_connected(&server_id)?;
            let descriptors = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .list_resources(&managed.config.id, &managed.config.name)?;
            managed.status = ServerStatus::Ready;
            descriptors
        };
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
        let contents = {
            let managed = self.ensure_connected(&server_id)?;
            let result = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .read_resource(&request.uri)?;
            managed.status = ServerStatus::Ready;
            result
        };
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
        let managed = self.ensure_connected(&server_id)?;
        managed
            .process
            .as_mut()
            .ok_or_else(|| BackendError::protocol("missing MCP process"))?
            .subscribe_resource(&request.uri)?;
        managed.status = ServerStatus::Ready;
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
        let managed = self.ensure_connected(&server_id)?;
        managed
            .process
            .as_mut()
            .ok_or_else(|| BackendError::protocol("missing MCP process"))?
            .unsubscribe_resource(&request.uri)?;
        managed.status = ServerStatus::Ready;
        Ok(json!({ "uri": request.uri }))
    }

    pub(crate) fn list_resource_templates(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: ResourceRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let templates = {
            let managed = self.ensure_connected(&server_id)?;
            let result = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .list_resource_templates(&managed.config.id, &managed.config.name)?;
            managed.status = ServerStatus::Ready;
            result
        };
        Ok(json!({ "templates": templates }))
    }

    pub(crate) fn list_prompts(&mut self, payload: Value) -> Result<Value, BackendError> {
        let request: PromptRequest = serde_json::from_value(payload)?;
        let server_id = self.resolve_server_identity(
            request.server_id,
            request.server_name,
            request.server,
        )?;
        let prompts = {
            let managed = self.ensure_connected(&server_id)?;
            let result = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .list_prompts(&managed.config.id, &managed.config.name)?;
            managed.status = ServerStatus::Ready;
            result
        };
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
        let result = {
            let managed = self.ensure_connected(&server_id)?;
            let result = managed
                .process
                .as_mut()
                .ok_or_else(|| BackendError::protocol("missing MCP process"))?
                .get_prompt(&request.name, request.arguments)?;
            managed.status = ServerStatus::Ready;
            result
        };
        Ok(json!({
            "description": result.description,
            "messages": result.messages,
        }))
    }
}
