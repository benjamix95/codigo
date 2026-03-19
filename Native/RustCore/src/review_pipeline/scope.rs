pub fn parse_review_scope(prompt: &str) -> (String, Option<String>) {
    let limit = prompt.find("## Conversation context (recent)").unwrap_or(prompt.len());
    let searchable = &prompt[..limit];
    let marker = "[REVIEW_SCOPE:";
    if let Some(start) = searchable.find(marker) {
        let after = &searchable[start + marker.len()..];
        if let Some(end_rel) = after.find(']') {
            let raw = after[..end_rel].trim().to_lowercase();
            let scope = match raw.as_str() {
                "staged" | "uncommitted" | "workspace" => Some(raw),
                _ => None,
            };
            if let Some(scope) = scope {
                let mut clean = String::new();
                clean.push_str(&searchable[..start]);
                clean.push_str(&after[end_rel + 1..]);
                clean.push_str(&prompt[limit..]);
                let trimmed = clean.trim();
                return (
                    if trimmed.is_empty() { "Review all changes".to_string() } else { trimmed.to_string() },
                    Some(scope),
                );
            }
        }
    }
    (prompt.to_string(), None)
}

pub fn infer_review_scope(prompt: &str) -> String {
    infer_review_scope_optional(prompt).unwrap_or_else(|| "uncommitted".to_string())
}

pub fn infer_review_scope_optional(prompt: &str) -> Option<String> {
    let lower = prompt.to_lowercase();
    if lower.contains("[review_scope:staged]")
        || lower.contains("/review-staged")
        || lower.contains("review only staged changes")
        || lower.contains("staged diff only")
    {
        return Some("staged".to_string());
    }
    if lower.contains("[review_scope:uncommitted]") || lower.contains("/review-uncommitted") {
        return Some("uncommitted".to_string());
    }
    if lower.contains("[review_scope:workspace]")
        || lower.contains("/review-workspace")
        || lower.contains("review the workspace")
        || lower.contains("review the repository")
        || lower.contains("review the codebase")
    {
        return Some("workspace".to_string());
    }
    None
}

pub fn parse_against_ref(prompt: &str) -> (String, Option<String>) {
    let limit = prompt.find("## Conversation context (recent)").unwrap_or(prompt.len());
    let searchable = &prompt[..limit];
    let marker = "[AGAINST:";
    if let Some(start) = searchable.find(marker) {
        let after = &searchable[start + marker.len()..];
        if let Some(end_rel) = after.find(']') {
            let reference = after[..end_rel].trim().to_string();
            let mut clean = String::new();
            clean.push_str(&searchable[..start]);
            clean.push_str(&after[end_rel + 1..]);
            clean.push_str(&prompt[limit..]);
            let trimmed = clean.trim();
            return (
                if trimmed.is_empty() { "Review all changes".to_string() } else { trimmed.to_string() },
                if reference.is_empty() { None } else { Some(reference) },
            );
        }
    }
    (prompt.to_string(), None)
}

pub fn review_scope_description(scope: &str, against_ref: Option<&str>) -> String {
    if let Some(reference) = against_ref {
        return format!("Changes against `{reference}`");
    }
    match scope {
        "staged" => "Staged changes".to_string(),
        "workspace" => "Workspace source files".to_string(),
        _ => "Uncommitted changes".to_string(),
    }
}

pub fn is_valid_against_ref_format(reference: &str) -> bool {
    let trimmed = reference.trim();
    if trimmed.is_empty() || trimmed.starts_with('-') || trimmed.ends_with(".lock") || trimmed.ends_with('.') {
        return false;
    }
    if trimmed.chars().any(|ch| ch.is_whitespace() || ch.is_control()) {
        return false;
    }
    for forbidden in [":", "?", "*", "[", "\\", "@{"] {
        if trimmed.contains(forbidden) {
            return false;
        }
    }
    true
}

pub fn normalized_against_ref_input(reference: &str) -> String {
    let trimmed = reference.trim();
    if trimmed.is_empty() || trimmed.contains("..") || !looks_like_commit_oid(trimmed) {
        return trimmed.to_string();
    }
    format!("{trimmed}^..{trimmed}")
}

pub fn normalized_against_ref_revision(reference: &str) -> String {
    let normalized = normalized_against_ref_input(reference);
    if normalized.contains("..") {
        return normalized;
    }
    format!("{normalized}...HEAD")
}

fn looks_like_commit_oid(reference: &str) -> bool {
    let trimmed = reference.trim();
    (7..=40).contains(&trimmed.len()) && trimmed.chars().all(|ch| ch.is_ascii_hexdigit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_scope_marker_and_ignores_context_tail() {
        let prompt = "[REVIEW_SCOPE:workspace] Review repo\n## Conversation context (recent)\nuser: [REVIEW_SCOPE:staged]";
        let (clean, scope) = parse_review_scope(prompt);
        assert_eq!(scope.as_deref(), Some("workspace"));
        assert_eq!(clean, "Review repo\n## Conversation context (recent)\nuser: [REVIEW_SCOPE:staged]");
    }

    #[test]
    fn parses_against_ref_marker() {
        let (clean, reference) = parse_against_ref("[AGAINST:HEAD~2] Review this diff");
        assert_eq!(reference.as_deref(), Some("HEAD~2"));
        assert_eq!(clean, "Review this diff");
    }

    #[test]
    fn infers_scope_only_when_prompt_contains_specific_signal() {
        assert_eq!(
            infer_review_scope_optional("Review ONLY staged changes and ignore unstaged."),
            Some("staged".to_string())
        );
        assert_eq!(
            infer_review_scope_optional("Please review the workspace architecture."),
            Some("workspace".to_string())
        );
        assert_eq!(infer_review_scope_optional("Review all changes"), None);
    }

    #[test]
    fn validates_and_normalizes_against_ref_like_swift() {
        assert!(is_valid_against_ref_format("HEAD~1"));
        assert!(!is_valid_against_ref_format("ref with space"));
        assert_eq!(normalized_against_ref_input("1e72c30"), "1e72c30^..1e72c30");
        assert_eq!(normalized_against_ref_revision("main"), "main...HEAD");
    }
}
