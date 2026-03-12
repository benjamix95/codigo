use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

pub fn handle(
    name: &str,
    _workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_web_fetch" => Some(web_fetch(arguments)),
        "coderide_web_search" => Some(web_search(arguments)),
        _ => None,
    }
}

fn web_fetch(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let mut url = string_arg(arguments, "url");
    if url.is_empty() {
        return CallToolResult::error("Error: 'url' parameter is required");
    }
    if !url.contains("://") {
        url = format!("https://{url}");
    }
    match Command::new("curl")
        .args(["-LfsSL", "--max-time", "20", url.as_str()])
        .output()
    {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout);
            CallToolResult::text(text.chars().take(12_000).collect::<String>())
        }
        Ok(output) => CallToolResult::error(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ),
        Err(error) => CallToolResult::error(error.to_string()),
    }
}

fn web_search(arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Error: 'query' parameter is required");
    }
    let encoded = query.replace(' ', "+");
    let url = format!("https://duckduckgo.com/html/?q={encoded}");
    match Command::new("curl")
        .args(["-LfsSL", "--max-time", "20", url.as_str()])
        .output()
    {
        Ok(output) if output.status.success() => {
            let html = String::from_utf8_lossy(&output.stdout);
            let mut lines = Vec::new();
            for line in html.lines() {
                if line.contains("result__title") || line.contains("result__snippet") {
                    let plain = strip_tags(line).trim().to_string();
                    if !plain.is_empty() {
                        lines.push(plain);
                    }
                }
                if lines.len() >= 10 {
                    break;
                }
            }
            if lines.is_empty() {
                CallToolResult::text("No search results found.")
            } else {
                CallToolResult::text(lines.join("\n"))
            }
        }
        Ok(output) => CallToolResult::error(
            String::from_utf8_lossy(&output.stderr).trim().to_string(),
        ),
        Err(error) => CallToolResult::error(error.to_string()),
    }
}

fn strip_tags(input: &str) -> String {
    let mut output = String::new();
    let mut inside_tag = false;
    for ch in input.chars() {
        match ch {
            '<' => inside_tag = true,
            '>' => inside_tag = false,
            _ if !inside_tag => output.push(ch),
            _ => {}
        }
    }
    output
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}
