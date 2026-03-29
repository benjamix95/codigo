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
    let raw_url = string_arg(arguments, "url");
    if raw_url.is_empty() {
        return CallToolResult::error("Error: 'url' parameter is required");
    }
    let url = match normalize_http_url(&raw_url) {
        Ok(url) => url,
        Err(message) => return CallToolResult::error(message),
    };
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
    let url = duckduckgo_search_url(&query);
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

fn normalize_http_url(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("Error: 'url' parameter is required".to_string());
    }
    if trimmed
        .chars()
        .any(|ch| ch.is_ascii_control() || matches!(ch, ' ' | '\t'))
    {
        return Err("Error: URL contains invalid whitespace/control characters".to_string());
    }

    let normalized = if trimmed.contains("://") {
        trimmed.to_string()
    } else {
        format!("https://{trimmed}")
    };

    let Some((scheme, remainder)) = normalized.split_once("://") else {
        return Err("Error: invalid URL format".to_string());
    };
    match scheme.to_ascii_lowercase().as_str() {
        "http" | "https" => {}
        _ => {
            return Err("Error: only http:// and https:// URLs are allowed".to_string());
        }
    }
    if remainder.is_empty() || remainder.starts_with('/') {
        return Err("Error: URL must include a host".to_string());
    }

    Ok(normalized)
}

fn duckduckgo_search_url(query: &str) -> String {
    format!(
        "https://duckduckgo.com/html/?q={}",
        form_urlencode_component(query)
    )
}

fn form_urlencode_component(input: &str) -> String {
    let mut encoded = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                encoded.push(byte as char);
            }
            b' ' => encoded.push('+'),
            _ => encoded.push_str(&format!("%{:02X}", byte)),
        }
    }
    encoded
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
    use super::{
        duckduckgo_search_url, format_curl_max_time, normalize_http_url,
        resolve_timeout_seconds,
    };
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

    #[test]
    fn fetch_rejects_non_http_scheme() {
        let error = normalize_http_url("file:///etc/passwd").unwrap_err();
        assert!(error.contains("only http:// and https://"));
    }

    #[test]
    fn fetch_defaults_to_https_when_scheme_missing() {
        assert_eq!(
            normalize_http_url("example.com/docs").unwrap(),
            "https://example.com/docs"
        );
    }

    #[test]
    fn search_url_percent_encodes_reserved_characters() {
        let url = duckduckgo_search_url("rust & mcp? 100%");
        assert!(url.ends_with("rust+%26+mcp%3F+100%25"));
    }
}
