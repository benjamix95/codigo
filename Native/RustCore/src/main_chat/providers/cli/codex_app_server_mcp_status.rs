use crate::main_chat::providers::common::string_value;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CodexMCPStartupStatus {
    pub(crate) name: String,
    pub(crate) status: String,
    pub(crate) error: Option<String>,
}

pub(crate) fn parse_codex_mcp_startup_status(
    payload: &Value,
) -> Option<CodexMCPStartupStatus> {
    let name = payload.get("name").and_then(string_value)?;
    let status = payload
        .get("status")
        .and_then(string_value)?
        .trim()
        .to_lowercase();
    let error = payload
        .get("error")
        .and_then(string_value)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    Some(CodexMCPStartupStatus {
        name,
        status,
        error,
    })
}

pub(crate) fn codex_mcp_startup_status_payload(
    status: &CodexMCPStartupStatus,
) -> BTreeMap<String, String> {
    let mut payload = BTreeMap::from([
        ("name".to_string(), status.name.clone()),
        ("status".to_string(), status.status.clone()),
        ("title".to_string(), format!("MCP server • {}", status.name)),
    ]);
    if let Some(error) = &status.error {
        payload.insert("error".to_string(), error.clone());
        payload.insert("detail".to_string(), error.clone());
    }
    payload
}

pub(crate) fn codex_required_mcp_startup_failure(
    status: &CodexMCPStartupStatus,
) -> Option<String> {
    guard_required_failure(status)
}

fn guard_required_failure(status: &CodexMCPStartupStatus) -> Option<String> {
    if status.name != "coderide" || status.status != "failed" {
        return None;
    }

    let detail = status
        .error
        .as_deref()
        .unwrap_or("MCP startup failed without an error message");
    Some(format!("coderide MCP startup failed: {detail}"))
}

#[cfg(test)]
mod tests {
    use super::{
        codex_mcp_startup_status_payload, codex_required_mcp_startup_failure,
        parse_codex_mcp_startup_status,
    };
    use serde_json::json;

    #[test]
    fn parse_startup_status_reads_name_status_and_error() {
        let payload = json!({
            "name": "coderide",
            "status": "failed",
            "error": "connection closed: initialize response"
        });

        let parsed = parse_codex_mcp_startup_status(&payload).expect("parsed status");
        assert_eq!(parsed.name, "coderide");
        assert_eq!(parsed.status, "failed");
        assert_eq!(
            parsed.error.as_deref(),
            Some("connection closed: initialize response")
        );
    }

    #[test]
    fn parse_startup_status_normalizes_status_and_ignores_blank_error() {
        let payload = json!({
            "name": "coderide",
            "status": " Ready ",
            "error": "   "
        });

        let parsed = parse_codex_mcp_startup_status(&payload).expect("parsed status");
        assert_eq!(parsed.status, "ready");
        assert_eq!(parsed.error, None);
    }

    #[test]
    fn required_failure_only_triggers_for_failed_coderide() {
        let payload = json!({
            "name": "coderide",
            "status": "failed",
            "error": "handshaking with MCP server failed"
        });
        let parsed = parse_codex_mcp_startup_status(&payload).expect("parsed status");
        let message =
            codex_required_mcp_startup_failure(&parsed).expect("required failure");
        assert!(message.contains("coderide MCP startup failed"));
        assert!(message.contains("handshaking with MCP server failed"));

        let codex_apps = json!({
            "name": "codex_apps",
            "status": "failed",
            "error": "transient"
        });
        let parsed_apps = parse_codex_mcp_startup_status(&codex_apps).expect("parsed status");
        assert_eq!(codex_required_mcp_startup_failure(&parsed_apps), None);
    }

    #[test]
    fn startup_status_payload_keeps_error_in_detail() {
        let payload = json!({
            "name": "coderide",
            "status": "failed",
            "error": "initialize response"
        });
        let parsed = parse_codex_mcp_startup_status(&payload).expect("parsed status");
        let raw = codex_mcp_startup_status_payload(&parsed);
        assert_eq!(raw.get("name").map(String::as_str), Some("coderide"));
        assert_eq!(raw.get("status").map(String::as_str), Some("failed"));
        assert_eq!(raw.get("detail").map(String::as_str), Some("initialize response"));
    }
}
