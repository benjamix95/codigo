use crate::backend::Backend;
use crate::mcp_process::flatten_tool_content;
use crate::protocol::{BatchCallRequest, BatchCallResultItem};
use serde_json::{json, Value};

impl Backend {
    pub(crate) fn call_tools_batch(&mut self, payload: Value) -> Result<Value, crate::error::BackendError> {
        let request: BatchCallRequest = serde_json::from_value(payload)?;
        let mut results: Vec<BatchCallResultItem> = Vec::with_capacity(request.calls.len());

        for call in request.calls {
            let outcome = self.call_batch_item(call);
            results.push(outcome);
        }

        Ok(json!({ "results": results }))
    }

    fn call_batch_item(&mut self, call: crate::protocol::BatchCallItem) -> BatchCallResultItem {
        let resolved = self.resolve_server_identity(call.server_id, call.server_name, call.server);
        let server_id = match resolved {
            Ok(server_id) => server_id,
            Err(error) => {
                return BatchCallResultItem {
                    index: call.index,
                    server_id: String::new(),
                    server_name: String::new(),
                    content: String::new(),
                    is_error: true,
                    error: Some(error.to_string()),
                };
            }
        };

        let config = match self.managed_server(&server_id) {
            Ok(managed) => managed.config.clone(),
            Err(error) => {
                return BatchCallResultItem {
                    index: call.index,
                    server_id,
                    server_name: String::new(),
                    content: String::new(),
                    is_error: true,
                    error: Some(error.to_string()),
                };
            }
        };

        let server_name = config.name.clone();
        let call_result = self.with_process_for_server(&server_id, "call_tools_batch", |process, _| {
            process.call_tool(&call.tool_name, call.arguments)
        });

        match call_result {
            Ok(result) => {
                BatchCallResultItem {
                    index: call.index,
                    server_id,
                    server_name,
                    content: flatten_tool_content(&result),
                    is_error: result.is_error.unwrap_or(false),
                    error: None,
                }
            }
            Err(error) => BatchCallResultItem {
                index: call.index,
                server_id,
                server_name,
                content: String::new(),
                is_error: true,
                error: Some(error.to_string()),
            },
        }
    }
}
