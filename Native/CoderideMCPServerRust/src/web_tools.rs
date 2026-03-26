use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

const DEFAULT_TIMEOUT_SECONDS: f64 = 30.0;
const MAX_TIMEOUT_SECONDS: f64 = 120.0;

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
    let timeout = timeout_arg(arguments);
    match Command::new("curl")
        .args(["-LfsSL", "--max-time", &timeout, url.as_str()])
        .output()
    {
        Ok(output) if output.status.success() => {
            let text = String::from_utf8_lossy(&output.stdout);
            CallToolResult::text(text.chars().take(12_000).collect::<String>())
        }
        Ok(output) => {
            let code = output.status.code().unwrap_or(-1);
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if code == 28 {
                CallToolResult::error(format!("Request timed out after {timeout}s"))
            } else if stderr.is_empty() {
                CallToolResult::error(format!("curl failed with exit code {code}"))
            } else {
                CallToolResult::error(stderr)
            }
        }
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
    let timeout = timeout_arg(arguments);
    match Command::new("curl")
        .args(["-LfsSL", "--max-time", &timeout, url.as_str()])
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
        Ok(output) => {
            let code = output.status.code().unwrap_or(-1);
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if code == 28 {
                CallToolResult::error(format!("Search timed out after {timeout}s"))
            } else if stderr.is_empty() {
                CallToolResult::error(format!("curl failed with exit code {code}"))
            } else {
                CallToolResult::error(stderr)
            }
        }
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
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ")
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn timeout_arg(arguments: &BTreeMap<String, Value>) -> String {
    format_curl_max_time(resolve_timeout_seconds(arguments.get("timeout")))
}

/// Seconds for curl `--max-time` (supports fractional values; invalid / out of range → default).
fn resolve_timeout_seconds(value: Option<&Value>) -> f64 {
    let Some(value) = value else {
        return DEFAULT_TIMEOUT_SECONDS;
    };
    let parsed = value
        .as_f64()
        .or_else(|| value.as_i64().map(|i| i as f64))
        .or_else(|| value.as_u64().map(|u| u as f64))
        .or_else(|| value.as_str().and_then(|s| s.trim().parse::<f64>().ok()));
    let Some(secs) = parsed else {
        return DEFAULT_TIMEOUT_SECONDS;
    };
    if !secs.is_finite() || secs <= 0.0 || secs > MAX_TIMEOUT_SECONDS {
        DEFAULT_TIMEOUT_SECONDS
    } else {
        secs
    }
}

fn format_curl_max_time(secs: f64) -> String {
    let millis = (secs * 1000.0).round();
    let rounded = millis / 1000.0;
    if (rounded - rounded.round()).abs() < 1e-6 {
        format!("{}", rounded as i64)
    } else {
        let s = format!("{rounded:.3}");
        s.trim_end_matches('0')
            .trim_end_matches('.')
            .to_string()
    }
}

#[cfg(test)]
mod timeout_tests {
    use super::{format_curl_max_time, resolve_timeout_seconds};
    use serde_json::json;

    #[test]
    fn fractional_timeout_is_preserved_not_truncated_to_zero() {
        let secs = resolve_timeout_seconds(Some(&json!(0.5)));
        assert!((secs - 0.5).abs() < 1e-6, "got {secs}");
        assert_eq!(format_curl_max_time(secs), "0.5");
    }

    #[test]
    fn string_decimal_timeout_parses() {
        assert!((resolve_timeout_seconds(Some(&json!("45.25"))) - 45.25).abs() < 1e-6);
    }

    #[test]
    fn out_of_range_falls_back_to_default() {
        assert_eq!(resolve_timeout_seconds(Some(&json!(200.0))), 30.0);
    }
}
