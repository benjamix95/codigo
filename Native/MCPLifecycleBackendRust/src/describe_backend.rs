use crate::backend::Backend;
use crate::protocol::ListToolsRequest;
use serde_json::{json, Value};

impl Backend {
    pub(crate) fn describe_tool(
        &mut self,
        payload: Value,
    ) -> Result<Value, crate::error::BackendError> {
        let request: ListToolsRequest = serde_json::from_value(payload)?;
        let Some(tool_name) = request.tool_name.filter(|value| !value.trim().is_empty()) else {
            return Err(crate::error::BackendError::invalid("toolName is required"));
        };

        let server_id =
            self.resolve_server_identity(request.server_id, request.server_name, request.server)?;
        let tool =
            self.with_process_for_server(&server_id, "describe_tool", |process, config| {
                let tools = process.list_tools(&config.id, &config.name)?;
                tools
                    .into_iter()
                    .find(|tool| tool.name == tool_name)
                    .ok_or_else(|| {
                        crate::error::BackendError::not_found(format!(
                            "unknown toolName: {tool_name}"
                        ))
                    })
            })?;

        Ok(json!({ "tool": tool }))
    }
}
