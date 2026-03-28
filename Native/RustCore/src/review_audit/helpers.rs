use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;

// ---------------------------------------------------------------------------
// Language detection
// ---------------------------------------------------------------------------

/// Supported languages for multi-language audit.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Lang {
    Swift,
    Rust,
    TypeScript,
    Python,
    Go,
    Other,
}

/// Detect the programming language from a file path extension.
pub(crate) fn detect_language(file: &str) -> Lang {
    let lower = file.to_lowercase();
    if lower.ends_with(".swift") || lower.ends_with(".m") || lower.ends_with(".mm") || lower.ends_with(".h") {
        Lang::Swift
    } else if lower.ends_with(".rs") {
        Lang::Rust
    } else if lower.ends_with(".ts") || lower.ends_with(".tsx") || lower.ends_with(".js") || lower.ends_with(".jsx") || lower.ends_with(".mjs") || lower.ends_with(".cjs") {
        Lang::TypeScript
    } else if lower.ends_with(".py") || lower.ends_with(".pyi") {
        Lang::Python
    } else if lower.ends_with(".go") {
        Lang::Go
    } else {
        Lang::Other
    }
}

/// Check if a file path indicates a test, mock, or fixture file.
pub(crate) fn is_test_or_mock_file(file: &str) -> bool {
    let lower = file.to_lowercase();
    let segments: Vec<&str> = lower.split('/').collect();
    // Check path segments
    for seg in &segments {
        if *seg == "tests" || *seg == "test" || *seg == "__tests__"
            || *seg == "mocks" || *seg == "mock" || *seg == "__mocks__"
            || *seg == "fixtures" || *seg == "fixture"
            || *seg == "testdata" || *seg == "test_data"
            || *seg == "stubs"
        {
            return true;
        }
    }
    // Check filename
    let filename = segments.last().unwrap_or(&"");
    filename.contains("test") || filename.contains("mock")
        || filename.contains("fixture") || filename.contains("stub")
        || filename.contains("spec") || filename.contains("fake")
        || filename.starts_with("test_") || filename.ends_with("_test.go")
        || filename.ends_with("_test.rs")
}

pub(crate) fn read_file_lines(file: &str, workspace_path: &str) -> Option<Vec<String>> {
    let path = PathBuf::from(workspace_path).join(file);
    fs::read_to_string(&path)
        .ok()
        .map(|c| c.lines().map(ToString::to_string).collect())
}

pub(crate) fn scoped_lines(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Vec<(String, Vec<String>)>, String> {
    let mut output = Vec::new();
    for file in scope_files {
        let path = PathBuf::from(workspace_path).join(&file);
        let content = fs::read_to_string(&path)
            .map_err(|err| format!("failed to read {}: {err}", path.display()))?;
        output.push((file, content.lines().map(ToString::to_string).collect()));
    }
    Ok(output)
}

pub(crate) fn workspace_contains_file_named(workspace_path: &str, target_file_name: &str) -> bool {
    let mut stack = vec![PathBuf::from(workspace_path)];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or_default();
            if path.is_dir() {
                if matches!(
                    file_name,
                    ".git"
                        | "DerivedData"
                        | "build"
                        | "node_modules"
                        | ".build"
                        | "dist"
                        | "target"
                ) {
                    continue;
                }
                stack.push(path);
                continue;
            }
            if file_name.eq_ignore_ascii_case(target_file_name) {
                return true;
            }
        }
    }
    false
}

pub(crate) fn run_pattern_tool(
    tool_key: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
    category: &str,
    origin: &str,
    patterns: &[(&str, &str, &str, &str, f64)],
    empty_summary: &str,
    hit_summary: &str,
    metadata: Value,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            for (needle, severity, message, remediation, confidence) in patterns {
                if lower.contains(&needle.to_lowercase()) {
                    findings.push(make_finding(
                        severity,
                        category,
                        origin,
                        &file,
                        Some(index + 1),
                        message,
                        remediation,
                        Some(*confidence),
                        Some(line.trim()),
                        *severity == "critical",
                        Some(tool_key.to_string()),
                    ));
                }
            }
        }
    }
    Ok(make_result_standard(
        tool_key,
        findings,
        true,
        empty_summary,
        hit_summary,
        metadata,
    ))
}

pub(crate) fn make_finding(
    severity: &str,
    category: &str,
    origin: &str,
    file_path: &str,
    line_number: Option<usize>,
    message: &str,
    suggested_fix: &str,
    confidence: Option<f64>,
    evidence: Option<&str>,
    blocking: bool,
    source_tool: Option<String>,
) -> Value {
    json!({
        "id": format!("{}:{}:{}", file_path, line_number.unwrap_or(0), message),
        "severity": severity,
        "category": category,
        "origin": origin,
        "filePath": file_path,
        "lineNumber": line_number,
        "message": message,
        "suggestedFix": suggested_fix,
        "confidence": confidence,
        "evidence": evidence,
        "sourceTool": source_tool,
        "blocking": blocking,
        "status": "open",
        "comments": [],
        "createdAt": 0.0
    })
}

pub(crate) fn make_result_standard(
    tool_name: &str,
    findings: Vec<Value>,
    coverage_available: bool,
    empty_summary: &str,
    hit_summary: &str,
    metadata: Value,
) -> Value {
    let summary = if findings.is_empty() {
        empty_summary.to_string()
    } else {
        format!("{} {}", hit_summary, findings.len())
    };
    pack_payload(
        tool_name,
        findings,
        coverage_available,
        summary,
        metadata,
        vec![],
        vec![],
    )
}

pub(crate) fn pack_payload(
    tool_name: &str,
    findings: Vec<Value>,
    coverage_available: bool,
    summary: String,
    metadata: Value,
    adapters_used: Vec<String>,
    clusters: Vec<Value>,
) -> Value {
    let hint = metadata
        .get("verification_hint")
        .or_else(|| metadata.get("verificationHint"))
        .cloned();
    let verification_hints = match hint {
        Some(h) => vec![h],
        None => Vec::new(),
    };
    let adapters_json: Vec<Value> = adapters_used.iter().map(|s| json!(s)).collect();
    json!({
        "toolName": tool_name,
        "findings": findings,
        "durationMs": 1,
        "coverageAvailable": coverage_available,
        "summary": summary,
        "adaptersUsed": adapters_json,
        "verificationHints": verification_hints,
        "metadata": metadata,
        "clusters": clusters
    })
}
