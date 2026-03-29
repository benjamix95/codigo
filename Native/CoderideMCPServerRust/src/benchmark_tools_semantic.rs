use app_core_protocol::mcp::{CallToolResult, ToolContent};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn run_semantic_search_benchmark(
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> CallToolResult {
    let mode = benchmark_mode(arguments);
    let tag = optional_string(arguments, "tag").unwrap_or_else(default_timestamp_tag);
    let root = match repo_root(workspace) {
        Ok(value) => value,
        Err(message) => return CallToolResult::error(message),
    };
    let output_dir = root.join("docs/benchmarks/semantic-search");
    let _ = std::fs::create_dir_all(&output_dir);
    let output_json = output_dir.join(format!("{tag}-{mode}.json"));
    let log_file = output_dir.join(format!("{tag}-{mode}.log"));

    let mut cmd = Command::new("xcodebuild");
    cmd.current_dir(&root);
    cmd.env("SOLOCODE_SEMANTIC_BENCHMARK_OUTPUT", output_json.as_os_str());
    if mode == "full" {
        cmd.env("RUN_SEMANTIC_BENCHMARK", "1");
    } else {
        cmd.env_remove("RUN_SEMANTIC_BENCHMARK");
    }
    cmd.arg("test");
    cmd.arg("-project").arg("Solo Code.xcodeproj");
    cmd.arg("-scheme").arg("CoderEngineTests-Debug");
    cmd.arg("-destination").arg("platform=macOS");
    cmd.arg("-only-testing:CoderEngineTests/SemanticSearchBenchmarkTests/testSemanticSearchBenchmarkSynthetic10kFiles");

    let output = match cmd.output() {
        Ok(value) => value,
        Err(err) => return CallToolResult::error(format!("benchmark_semantic_search failed to launch: {err}")),
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let _ = std::fs::write(&log_file, format!("{stdout}\n{stderr}"));

    if !output.status.success() {
        return failure_with_structured(
            format!("benchmark_semantic_search failed ({mode}, tag={tag})"),
            json!({
                "tool": "benchmark_semantic_search",
                "mode": mode,
                "tag": tag,
                "status": "failed",
                "stdout": stdout,
                "stderr": stderr,
                "log_file": log_file.display().to_string(),
            }),
        );
    }

    success_with_structured(
        format!("benchmark_semantic_search {mode} {tag}"),
        json!({
            "tool": "benchmark_semantic_search",
            "mode": mode,
            "tag": tag,
            "status": "completed",
            "stdout": stdout,
            "stderr": stderr,
            "output_json": output_json.display().to_string(),
            "log_file": log_file.display().to_string(),
        }),
    )
}

fn benchmark_mode(arguments: &BTreeMap<String, Value>) -> String {
    match string_arg(arguments, "mode").to_lowercase().as_str() {
        "full" => "full".to_string(),
        _ => "smoke".to_string(),
    }
}

fn repo_root(workspace: &Path) -> Result<PathBuf, String> {
    let mut current = workspace.canonicalize().unwrap_or_else(|_| workspace.to_path_buf());
    loop {
        if current.join("Tests/CoderEngineTests/SemanticSearch/SemanticSearchBenchmarkTests.swift").exists() {
            return Ok(current);
        }
        if !current.pop() {
            break;
        }
    }
    Err("Unable to locate repository root for semantic benchmark".to_string())
}

fn default_timestamp_tag() -> String {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(delta) => format!("semantic-benchmark-{}", delta.as_secs()),
        Err(_) => "semantic-benchmark-adhoc".to_string(),
    }
}

fn optional_string(arguments: &BTreeMap<String, Value>, key: &str) -> Option<String> {
    let value = string_arg(arguments, key);
    if value.trim().is_empty() { None } else { Some(value) }
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    match arguments.get(key) {
        Some(Value::String(text)) => text.clone(),
        Some(Value::Bool(flag)) => flag.to_string(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Null) | None => String::new(),
        Some(other) => other.to_string(),
    }
}

fn success_with_structured(text: String, structured: Value) -> CallToolResult {
    CallToolResult {
        content: vec![ToolContent::Text { text }],
        structured_content: Some(structured),
        is_error: None,
    }
}

fn failure_with_structured(text: String, structured: Value) -> CallToolResult {
    CallToolResult {
        content: vec![ToolContent::Text { text }],
        structured_content: Some(structured),
        is_error: Some(true),
    }
}

#[cfg(test)]
mod tests {
    use super::{benchmark_mode, repo_root};
    use serde_json::json;
    use std::collections::BTreeMap;
    use std::path::Path;

    #[test]
    fn benchmark_mode_defaults_to_smoke() {
        let args = BTreeMap::new();
        assert_eq!(benchmark_mode(&args), "smoke");
    }

    #[test]
    fn benchmark_mode_supports_full() {
        let mut args = BTreeMap::new();
        args.insert("mode".to_string(), json!("full"));
        assert_eq!(benchmark_mode(&args), "full");
    }

    #[test]
    fn repo_root_finds_semantic_benchmark_test() {
        let root = repo_root(Path::new("/Users/benjaminstoica/SoloCode")).expect("repo root");
        assert!(root.join("Tests/CoderEngineTests/SemanticSearch/SemanticSearchBenchmarkTests.swift").exists());
    }
}
