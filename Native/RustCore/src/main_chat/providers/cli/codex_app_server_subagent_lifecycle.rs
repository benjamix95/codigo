use std::collections::BTreeMap;

pub(crate) fn is_subagent_launch_ack_payload(payload: &BTreeMap<String, String>) -> bool {
    let tool = payload
        .get("mcp_tool")
        .or_else(|| payload.get("tool"))
        .or_else(|| payload.get("name"))
        .cloned()
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    if !tool.contains("subagent_") {
        return false;
    }
    let text = payload
        .get("output")
        .or_else(|| payload.get("detail"))
        .or_else(|| payload.get("title"))
        .cloned()
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    text.starts_with("ok — subagent")
        || text.starts_with("ok - subagent")
        || (text.contains("subagent") && text.contains("launched"))
}

#[cfg(test)]
mod tests {
    use super::is_subagent_launch_ack_payload;
    use std::collections::BTreeMap;

    #[test]
    fn detects_launch_ack_for_coderide_subagent() {
        let payload = BTreeMap::from([
            ("mcp_tool".to_string(), "coderide_subagent_explorer".to_string()),
            ("output".to_string(), "OK — subagent Explorer launched".to_string()),
        ]);
        assert!(is_subagent_launch_ack_payload(&payload));
    }

    #[test]
    fn ignores_non_subagent_tool_payloads() {
        let payload = BTreeMap::from([
            ("mcp_tool".to_string(), "coderide_read".to_string()),
            ("output".to_string(), "OK — file read complete".to_string()),
        ]);
        assert!(!is_subagent_launch_ack_payload(&payload));
    }
}
