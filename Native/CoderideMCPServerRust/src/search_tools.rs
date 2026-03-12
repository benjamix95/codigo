use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn handle(name: &str, workspace: &Path, arguments: &BTreeMap<String, Value>) -> Option<CallToolResult> {
    match name {
        "coderide_glob" => Some(glob(workspace, arguments)),
        "coderide_grep" => Some(grep(workspace, arguments)),
        "coderide_read_range" => Some(read_range(workspace, arguments)),
        "coderide_find_files" => Some(find_files(workspace, arguments)),
        "coderide_find_symbol" => Some(find_symbol(workspace, arguments)),
        "coderide_find_references" => Some(find_references(workspace, arguments)),
        "coderide_file_outline" => Some(file_outline(workspace, arguments)),
        "coderide_codebase_search" => Some(codebase_search(workspace, arguments)),
        _ => None,
    }
}

#[cfg_attr(not(test), allow(dead_code))]
pub fn supports(name: &str) -> bool {
    matches!(
        name,
        "coderide_glob"
            | "coderide_grep"
            | "coderide_read_range"
            | "coderide_find_files"
            | "coderide_find_symbol"
            | "coderide_find_references"
            | "coderide_file_outline"
            | "coderide_codebase_search"
    )
}

fn glob(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let pattern = string_arg(arguments, "pattern");
    if pattern.is_empty() {
        return CallToolResult::error("Error: 'pattern' parameter is required");
    }
    match run_rg(workspace, &["--files", "-g", pattern.as_str()]) {
        Ok(output) if output.is_empty() => CallToolResult::text("No matches found."),
        Ok(output) => CallToolResult::text(output),
        Err(()) => CallToolResult::error("Error: failed to execute rg"),
    }
}

fn grep(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    let pattern = if query.is_empty() { string_arg(arguments, "pattern") } else { query };
    if pattern.is_empty() {
        return CallToolResult::error("Error: 'query' parameter is required");
    }
    match run_rg(workspace, &["-n", "--no-heading", pattern.as_str()]) {
        Ok(output) if output.is_empty() => CallToolResult::text("No matches found."),
        Ok(output) => CallToolResult::text(output),
        Err(()) => CallToolResult::error("Error: failed to execute rg"),
    }
}

fn read_range(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path = resolve_path(workspace, string_arg(arguments, "path"));
    let start = int_arg(arguments, "start").or_else(|| int_arg(arguments, "start_line")).unwrap_or(1).max(1) as usize;
    let end = int_arg(arguments, "end").or_else(|| int_arg(arguments, "end_line")).unwrap_or(0) as usize;
    let Ok(content) = fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let lines = content.lines().collect::<Vec<_>>();
    let safe_end = if end > 0 { end.min(lines.len()) } else { (start + 200).min(lines.len()) };
    if start == 0 || start > safe_end || start > lines.len() {
        return CallToolResult::error("Invalid line range");
    }
    let output = lines[(start - 1)..safe_end]
        .iter()
        .enumerate()
        .map(|(offset, line)| format!("{}: {}", start + offset, line))
        .collect::<Vec<_>>()
        .join("\n");
    CallToolResult::text(output)
}

fn find_files(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    let pattern = if query.is_empty() { string_arg(arguments, "pattern") } else { query };
    if pattern.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let extension_filter = string_arg(arguments, "extension");
    let output = run_rg(workspace, &["--files"]);
    let Ok(output) = output else { return CallToolResult::error("Error: failed to enumerate files"); };
    let mut matches = output
        .lines()
        .filter(|line| extension_filter.is_empty() || line.ends_with(&format!(".{extension_filter}")))
        .filter(|line| line.contains(&pattern) || glob_like_match(line, &pattern))
        .take(50)
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    matches.sort();
    if matches.is_empty() {
        CallToolResult::text(format!("No files found matching '{}'", pattern))
    } else {
        CallToolResult::text(matches.join("\n"))
    }
}

fn find_symbol(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let regex = format!(r"\b(class|struct|enum|protocol|func|let|var)\s+{}\b", regex_escape(&query));
    let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "-e", &regex]) else {
        return CallToolResult::error("Error: failed to search symbols");
    };
    let lines = output.lines().take(20).collect::<Vec<_>>();
    if lines.is_empty() {
        return CallToolResult::text(format!("Symbol '{}' not found in the codebase", query));
    }
    CallToolResult::text(format!(
        "Found {} definition(s) for '{}':\n\n{}",
        lines.len(),
        query,
        lines.join("\n")
    ))
}

fn find_references(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let regex = format!(r"\b{}\b", regex_escape(&query));
    let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "-e", &regex]) else {
        return CallToolResult::error("Error: failed to search references");
    };
    let lines = output.lines().take(100).collect::<Vec<_>>();
    if lines.is_empty() {
        return CallToolResult::text(format!("No references found for '{}'", query));
    }
    CallToolResult::text(format!(
        "Found {} reference(s) for '{}':\n{}",
        lines.len(),
        query,
        lines.join("\n")
    ))
}

fn file_outline(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let path_arg = string_arg(arguments, "path");
    if path_arg.is_empty() {
        return CallToolResult::error("Missing 'path' argument");
    }
    let path = resolve_path(workspace, path_arg);
    let Ok(content) = fs::read_to_string(&path) else {
        return CallToolResult::error(format!("Error: unable to read '{}'", path.display()));
    };
    let mut items = Vec::new();
    for (index, line) in content.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.starts_with("import ") || trimmed.starts_with("class ") || trimmed.starts_with("struct ")
            || trimmed.starts_with("enum ") || trimmed.starts_with("protocol ") || trimmed.starts_with("func ")
        {
            items.push(format!("{}: {}", index + 1, trimmed));
        }
    }
    if items.is_empty() {
        CallToolResult::text(format!("No symbols found in '{}'. File may not be indexed.", path.display()))
    } else {
        CallToolResult::text(items.join("\n"))
    }
}

fn codebase_search(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    let Ok(output) = run_rg(workspace, &["-n", "--no-heading", "-e", &query]) else {
        return CallToolResult::error("Error: failed to search codebase");
    };
    let lines = output.lines().take(50).collect::<Vec<_>>();
    if lines.is_empty() {
        return CallToolResult::text(format!("No symbols found matching '{}'", query));
    }
    CallToolResult::text(lines.join("\n"))
}

fn run_rg(workspace: &Path, args: &[&str]) -> Result<String, ()> {
    let output = Command::new("rg").args(args).current_dir(workspace).output().map_err(|_| ())?;
    if output.status.success() || output.status.code() == Some(1) {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(())
    }
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments.get(key).and_then(Value::as_str).unwrap_or_default().trim().to_string()
}

fn int_arg(arguments: &BTreeMap<String, Value>, key: &str) -> Option<i64> {
    arguments.get(key).and_then(Value::as_i64)
}

fn resolve_path(workspace: &Path, input: String) -> PathBuf {
    let path = Path::new(input.trim());
    if path.is_absolute() { path.to_path_buf() } else { workspace.join(path) }
}

fn regex_escape(input: &str) -> String {
    regex_chars(input).chars().fold(String::new(), |mut acc, ch| {
        if ".+*?^$()[]{}|\\".contains(ch) { acc.push('\\'); }
        acc.push(ch);
        acc
    })
}

fn regex_chars(input: &str) -> String {
    input.trim().to_string()
}

fn glob_like_match(path: &str, pattern: &str) -> bool {
    if !pattern.contains('*') {
        return path.contains(pattern);
    }
    let parts = pattern.split('*').filter(|part| !part.is_empty()).collect::<Vec<_>>();
    if parts.is_empty() {
        return true;
    }
    let mut cursor = 0usize;
    for part in parts {
        let Some(position) = path[cursor..].find(part) else { return false };
        cursor += position + part.len();
    }
    true
}
