use super::models::ReviewTask;
use std::collections::HashSet;

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
    let lower = prompt.to_lowercase();
    if lower.contains("[review_scope:staged]")
        || lower.contains("/review-staged")
        || lower.contains("review only staged changes")
        || lower.contains("staged diff only")
    {
        return "staged".to_string();
    }
    if lower.contains("[review_scope:workspace]")
        || lower.contains("/review-workspace")
        || lower.contains("review the workspace")
        || lower.contains("review the repository")
        || lower.contains("review the codebase")
    {
        return "workspace".to_string();
    }
    "uncommitted".to_string()
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

pub fn task_files(tasks: &[ReviewTask]) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut files = Vec::new();
    for task in tasks {
        for file in &task.files {
            if seen.insert(file.clone()) {
                files.push(file.clone());
            }
        }
    }
    files
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
}
