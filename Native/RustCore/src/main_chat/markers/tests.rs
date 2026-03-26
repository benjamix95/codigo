#[cfg(test)]
mod tests {
    use super::super::handle_request;
    use app_core_protocol::main_chat_markers::MainChatMarkersRequest;

    fn strip(input: &str, aggressive: bool) -> String {
        handle_request(MainChatMarkersRequest {
            schema_version: 1,
            operation: "strip_coderide_markers".to_string(),
            text: input.to_string(),
            aggressive: Some(aggressive),
        })
        .text
        .expect("sanitized text")
    }

    #[test]
    fn strip_removes_complete_and_incomplete_markers() {
        let input =
            "Before [CODERIDE:read|path=Sources/A.swift] after\nhalf [CODERIDE:grep|query=foo";
        let sanitized = strip(input, true);
        assert!(!sanitized.contains("CODERIDE"));
        assert!(sanitized.contains("Before"));
        assert!(sanitized.contains("after"));
        assert!(sanitized.contains("half"));
    }

    #[test]
    fn strip_keeps_code_fences_intact() {
        let input = "Before\n```swift\nlet marker = \"[CODERIDE:keep]\"\n```\nAfter";
        let sanitized = strip(input, true);
        assert!(sanitized.contains("```swift"));
        assert!(sanitized.contains("[CODERIDE:keep]"));
    }

    #[test]
    fn strip_removes_standalone_coderide_tool_line_even_on_fast_path() {
        let input = "coderide_subagent_explorer";
        let sanitized = strip(input, true);
        assert!(!sanitized.to_lowercase().contains("coderide_"));
        assert!(sanitized.trim().is_empty());
    }

    #[test]
    fn strip_keeps_coderide_tool_line_inside_code_fence() {
        let input = "Before\n```\ncoderide_subagent_explorer\n```\nAfter";
        let sanitized = strip(input, true);
        assert!(sanitized.contains("coderide_subagent_explorer"));
        assert!(sanitized.contains("After"));
    }

    #[test]
    fn strip_removes_list_item_coderide_tool_line() {
        let input = "- coderide_read\n\nHello";
        let sanitized = strip(input, true);
        assert!(!sanitized.to_lowercase().contains("coderide_"));
        assert!(sanitized.contains("Hello"));
    }

    #[test]
    fn strip_removes_policy_error_runs_and_coderide_only_lines() {
        let input = "Hello\n[Policy error] Emit before starting.\nRow\nThinking · [CODERIDE:policy_ack|hash=ab";
        let sanitized = strip(input, true);
        assert!(sanitized.contains("Hello"));
        assert!(sanitized.contains("Row"));
        assert!(!sanitized.to_lowercase().contains("policy error"));
        assert!(!sanitized.contains("CODERIDE"));
    }

    #[test]
    fn strip_removes_inline_marker_payloads() {
        let input = "Proceeding markers:plan_step|step_id=1|status=running|then continuing with the analysis.";
        let sanitized = strip(input, true);
        assert!(!sanitized.contains("plan_step|"));
        assert!(!sanitized.contains("step_id=1"));
        assert!(sanitized.contains("Proceeding"));
    }

    #[test]
    fn strip_non_aggressive_keeps_generic_key_values() {
        let input = "Current config:\nstatus=ok\nid=abc123\nnotes=visible value";
        let sanitized = strip(input, false);
        assert!(sanitized.contains("status=ok"));
        assert!(sanitized.contains("id=abc123"));
        assert!(sanitized.contains("notes=visible value"));
    }

    #[test]
    fn extract_last_operational_thinking_line_returns_last_matching_line() {
        let response = handle_request(MainChatMarkersRequest {
            schema_version: 1,
            operation: "extract_last_operational_thinking_line".to_string(),
            text: "Done\nExplored files\nReading config".to_string(),
            aggressive: None,
        });
        assert_eq!(response.text.as_deref(), Some("Reading config"));
    }
}
