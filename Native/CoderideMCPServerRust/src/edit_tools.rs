use app_core_protocol::mcp::{CallToolResult, ToolContent};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// Atomic write: write to temp file then rename, preventing partial writes.
fn atomic_write(path: &Path, content: &str) -> std::io::Result<()> {
    let tmp_path = path.with_extension("solocode-tmp");
    fs::write(&tmp_path, content)?;
    fs::rename(&tmp_path, path)
}

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_create_file" => Some(create_file(workspace, arguments)),
        "coderide_write" => Some(write_file(workspace, arguments)),
        "coderide_str_replace" => Some(str_replace(workspace, arguments)),
        "coderide_regex_replace" => Some(regex_replace(workspace, arguments)),
        _ => None,
    }
}

pub fn supports(name: &str) -> bool {
    matches!(
        name,
        "coderide_create_file"
            | "coderide_write"
            | "coderide_str_replace"
            | "coderide_regex_replace"
    )
}

fn create_file(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = match crate::workspace_paths::resolve_within_workspace(
        workspace,
        &string_arg(arguments, "path"),
    ) {
        Ok(p) => p,
        Err(msg) => return CallToolResult::error(msg),
    };
    if path.exists() {
        return CallToolResult::error(format!(
            "File already exists: {}. Use str_replace to edit or write to overwrite.",
            path.display()
        ));
    }
    let content = string_arg(arguments, "content");
    if let Some(parent) = path.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return CallToolResult::error(error.to_string());
        }
    }
    if let Err(error) = atomic_write(&path, &content) {
        return CallToolResult::error(error.to_string());
    }
    let line_count = count_lines(&content);
    success_with_structured(
        format!(
            "Created {}",
            path.file_name().and_then(|v| v.to_str()).unwrap_or("file")
        ),
        json!({
            "path": path.display().to_string(),
            "file": path.display().to_string(),
            "detail": format!("Created {} lines", line_count),
            "linesAdded": line_count.to_string()
        }),
    )
}

fn write_file(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = match crate::workspace_paths::resolve_within_workspace(
        workspace,
        &string_arg(arguments, "path"),
    ) {
        Ok(p) => p,
        Err(msg) => return CallToolResult::error(msg),
    };
    let content = string_arg(arguments, "content");
    let old_content = match fs::read_to_string(&path) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(err) => {
            return CallToolResult::error(format!(
                "cannot read {} for diff stats: {err}",
                path.display()
            ));
        }
    };
    if let Err(error) = atomic_write(&path, &content) {
        return CallToolResult::error(error.to_string());
    }
    let added = count_lines(&content).saturating_sub(count_lines(&old_content));
    let removed = count_lines(&old_content).saturating_sub(count_lines(&content));
    success_with_structured(
        format!("Edit {}", path.display()),
        json!({
            "path": path.display().to_string(),
            "file": path.display().to_string(),
            "linesAdded": added.to_string(),
            "linesRemoved": removed.to_string()
        }),
    )
}

fn str_replace(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = match crate::workspace_paths::resolve_within_workspace(
        workspace,
        &string_arg(arguments, "path"),
    ) {
        Ok(p) => p,
        Err(msg) => return CallToolResult::error(msg),
    };
    if !path.exists() {
        return CallToolResult::error(format!(
            "File not found: {}. Use create_file for new files.",
            path.display()
        ));
    }
    let old_string = string_arg(arguments, "old_string");
    if old_string.is_empty() {
        return CallToolResult::error("old_string is required and cannot be empty");
    }
    let new_string = string_arg(arguments, "new_string");
    let content = match fs::read_to_string(&path) {
        Ok(content) => content,
        Err(error) => return CallToolResult::error(error.to_string()),
    };
    let occurrences = content.matches(&old_string).count();
    if occurrences == 0 {
        return CallToolResult::error(format!("old_string not found in {}", path.display()));
    }
    if occurrences > 1 {
        return CallToolResult::error(format!(
            "old_string is not unique — found {} occurrences. Add more surrounding context to make it unique.",
            occurrences
        ));
    }
    let line_number = line_number_for(&content, &old_string).unwrap_or(1);
    let new_content = content.replacen(&old_string, &new_string, 1);
    if let Err(error) = atomic_write(&path, &new_content) {
        return CallToolResult::error(error.to_string());
    }
    success_with_structured(
        format!(
            "str_replace {}:{}",
            path.file_name().and_then(|v| v.to_str()).unwrap_or("file"),
            line_number
        ),
        json!({
            "path": path.display().to_string(),
            "file": path.display().to_string(),
            "detail": format!(
                "Replaced at line {} ({} lines → {} lines)",
                line_number,
                count_lines(&old_string),
                count_lines(&new_string)
            )
        }),
    )
}

fn regex_replace(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = match crate::workspace_paths::resolve_within_workspace(
        workspace,
        &string_arg(arguments, "path"),
    ) {
        Ok(p) => p,
        Err(msg) => return CallToolResult::error(msg),
    };
    if !path.exists() {
        return CallToolResult::error(format!("File not found: {}", path.display()));
    }
    let pattern = string_arg(arguments, "pattern");
    if pattern.is_empty() {
        return CallToolResult::error("pattern is required");
    }
    let flags = string_arg(arguments, "flags").to_lowercase();
    let pattern_for_regex = if flags.contains('i') && !pattern.trim_start().starts_with("(?i)") {
        format!("(?i){pattern}")
    } else {
        pattern
    };
    let replacement = string_arg(arguments, "replacement");
    let content = match fs::read_to_string(&path) {
        Ok(content) => content,
        Err(error) => return CallToolResult::error(error.to_string()),
    };
    let re = match Regex::new(&pattern_for_regex) {
        Ok(re) => re,
        Err(error) => return CallToolResult::error(format!("invalid regex: {error}")),
    };
    let replace_all = arguments
        .get("replace_all")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let replaced = if replace_all {
        re.replace_all(&content, replacement.as_str()).to_string()
    } else {
        re.replace(&content, replacement.as_str()).to_string()
    };
    if replaced == content {
        return CallToolResult::error(format!("pattern not found in {}", path.display()));
    }
    if let Err(error) = atomic_write(&path, &replaced) {
        return CallToolResult::error(error.to_string());
    }
    success_with_structured(
        format!(
            "regex_replace {}",
            path.file_name().and_then(|v| v.to_str()).unwrap_or("file")
        ),
        json!({
            "path": path.display().to_string(),
            "file": path.display().to_string(),
            "detail": "Replacement applied"
        }),
    )
}

fn success_with_structured(text: String, structured: Value) -> CallToolResult {
    CallToolResult {
        content: vec![ToolContent::Text { text }],
        structured_content: Some(structured),
        is_error: None,
    }
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn count_lines(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }
    text.lines().count().max(1)
}

fn line_number_for(content: &str, needle: &str) -> Option<usize> {
    content
        .find(needle)
        .map(|offset| content[..offset].chars().filter(|ch| *ch == '\n').count() + 1)
}
