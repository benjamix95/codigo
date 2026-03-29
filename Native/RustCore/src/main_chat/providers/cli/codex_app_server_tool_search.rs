use std::collections::{BTreeMap, HashSet};

#[derive(Default)]
pub(super) struct CodexToolSearchEmitter {
    pending_line: String,
    seen_keys: HashSet<String>,
}

impl CodexToolSearchEmitter {
    pub(super) fn consume_delta(&mut self, delta: &str) -> Vec<BTreeMap<String, String>> {
        if delta.is_empty() {
            return Vec::new();
        }
        self.pending_line.push_str(delta);
        let mut payloads = Vec::new();
        while let Some(pos) = self.pending_line.find('\n') {
            let line = self.pending_line[..pos].trim_end_matches('\r').to_string();
            self.pending_line = self.pending_line[pos + 1..].to_string();
            if let Some(payload) = self.parse_line(&line) {
                payloads.push(payload);
            }
        }
        payloads
    }

    pub(super) fn consume_completed_text(&mut self, text: &str) -> Vec<BTreeMap<String, String>> {
        let mut payloads = self.consume_delta(text);
        let trailing = std::mem::take(&mut self.pending_line);
        if let Some(payload) = self.parse_line(trailing.trim_end_matches('\r')) {
            payloads.push(payload);
        }
        payloads
    }

    fn parse_line(&mut self, line: &str) -> Option<BTreeMap<String, String>> {
        let trimmed = trimmed_line_payload(line);
        let selected = trimmed.strip_prefix("select:")?;
        let raw_candidates = selected
            .split(',')
            .map(str::trim)
            .filter(|candidate| !candidate.is_empty())
            .map(ToOwned::to_owned)
            .collect::<Vec<_>>();
        if raw_candidates.is_empty() {
            return None;
        }

        let display_candidates = raw_candidates
            .iter()
            .map(|candidate| normalize_display_tool_name(candidate))
            .collect::<Vec<_>>();
        let dedupe_key = display_candidates.join(",");
        if dedupe_key.is_empty() || !self.seen_keys.insert(dedupe_key.clone()) {
            return None;
        }

        let mut payload = BTreeMap::from([
            ("title".to_string(), "Tool search".to_string()),
            ("status".to_string(), "completed".to_string()),
            ("selection".to_string(), raw_candidates.join(",")),
            ("selected_tools".to_string(), display_candidates.join(",")),
            (
                "selected_count".to_string(),
                display_candidates.len().to_string(),
            ),
            ("detail".to_string(), display_candidates.join(", ")),
            (
                "output".to_string(),
                format!("select:{}", display_candidates.join(",")),
            ),
        ]);
        if display_candidates
            .iter()
            .any(|candidate| candidate.starts_with("coderide_"))
        {
            payload.insert("mcp_server".to_string(), "coderide".to_string());
        }
        Some(payload)
    }
}

fn trimmed_line_payload(line: &str) -> &str {
    let trimmed = line.trim();
    if let Some(rest) = trimmed.strip_prefix("- ") {
        return rest.trim();
    }
    if let Some(rest) = trimmed.strip_prefix("* ") {
        return rest.trim();
    }
    if let Some(rest) = trimmed.strip_prefix("+ ") {
        return rest.trim();
    }
    trimmed
}

fn normalize_display_tool_name(candidate: &str) -> String {
    let without_functions = candidate
        .trim()
        .strip_prefix("functions.")
        .unwrap_or(candidate.trim());
    if let Some(rest) = without_functions.strip_prefix("mcp__coderide__coderide_") {
        return format!("coderide_{rest}");
    }
    if let Some(rest) = without_functions.strip_prefix("mcp__") {
        return rest.to_string();
    }
    without_functions.to_string()
}

#[cfg(test)]
mod tests {
    use super::CodexToolSearchEmitter;

    #[test]
    fn emits_tool_search_from_split_delta() {
        let mut emitter = CodexToolSearchEmitter::default();
        assert!(emitter
            .consume_delta("select:mcp__coderide__coderide_g")
            .is_empty());

        let payloads = emitter.consume_delta("rep,mcp__coderide__coderide_read_range\n");
        assert_eq!(payloads.len(), 1);
        assert_eq!(
            payloads[0].get("selected_tools").map(String::as_str),
            Some("coderide_grep,coderide_read_range")
        );
        assert_eq!(
            payloads[0].get("mcp_server").map(String::as_str),
            Some("coderide")
        );
    }

    #[test]
    fn completed_text_dedupes_select_lines_already_emitted_from_deltas() {
        let mut emitter = CodexToolSearchEmitter::default();
        let initial = emitter.consume_delta("select:functions.mcp__coderide__coderide_read\n");
        assert_eq!(initial.len(), 1);

        let duplicate =
            emitter.consume_completed_text("select:functions.mcp__coderide__coderide_read");
        assert!(duplicate.is_empty());
    }

    #[test]
    fn ignores_non_select_lines() {
        let mut emitter = CodexToolSearchEmitter::default();
        assert!(emitter
            .consume_delta("Thinking about next step\n")
            .is_empty());
        assert!(emitter
            .consume_completed_text("No tool selection here")
            .is_empty());
    }
}
