use app_core_protocol::mcp::{CallToolResult, ToolContent};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

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
    let control_path = benchmark_control_path();
    write_benchmark_control(&control_path, &mode, &output_json);

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

    let started_at = Instant::now();
    let output = match cmd.output() {
        Ok(value) => value,
        Err(err) => return CallToolResult::error(format!("benchmark_semantic_search failed to launch: {err}")),
    };
    let wall_duration_ms = started_at.elapsed().as_millis() as u64;
    let _ = fs::remove_file(&control_path);

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

    ensure_benchmark_artifact(
        &output_json,
        &mode,
        &tag,
        &stdout,
        &stderr,
        wall_duration_ms,
    );

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
    for start in repo_root_candidates(workspace) {
        let mut current = start;
        loop {
            if current.join("Tests/CoderEngineTests/SemanticSearch/SemanticSearchBenchmarkTests.swift").exists() {
                return Ok(current);
            }
            if !current.pop() {
                break;
            }
        }
    }
    Err("Unable to locate repository root for semantic benchmark".to_string())
}

fn repo_root_candidates(workspace: &Path) -> Vec<PathBuf> {
    let mut candidates: Vec<PathBuf> = Vec::new();
    candidates.push(workspace.canonicalize().unwrap_or_else(|_| workspace.to_path_buf()));

    if let Ok(current_dir) = std::env::current_dir() {
        candidates.push(current_dir);
    }

    for key in ["PWD", "SRCROOT", "SOLOCODE_WORKSPACE_PATH"] {
        if let Ok(value) = std::env::var(key) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                candidates.push(PathBuf::from(trimmed));
            }
        }
    }

    let mut deduped: Vec<PathBuf> = Vec::new();
    for candidate in candidates {
        if !deduped.iter().any(|existing| existing == &candidate) {
            deduped.push(candidate);
        }
    }
    deduped
}

fn benchmark_file_count(mode: &str) -> usize {
    match mode {
        "full" => 10_000,
        _ => 200,
    }
}

fn benchmark_control_path() -> PathBuf {
    std::env::temp_dir().join("solocode-semantic-benchmark-config.json")
}

fn write_benchmark_control(path: &Path, mode: &str, output_json: &Path) {
    let payload = json!({
        "mode": mode,
        "output_json": output_json.display().to_string(),
    });
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(serialized) = serde_json::to_string(&payload) {
        let _ = fs::write(path, serialized);
    }
}

fn parse_test_duration_ms(output: &str) -> Option<u64> {
    output.lines().find_map(|line| {
        if !line.contains(" passed (") {
            return None;
        }
        let passed_index = line.find(" passed (")?;
        let tail = &line[passed_index + " passed (".len()..];
        let seconds_str = tail.split(" seconds").next()?.trim();
        let seconds = seconds_str.parse::<f64>().ok()?;
        Some((seconds * 1000.0).round() as u64)
    })
}

fn ensure_benchmark_artifact(
    output_json: &Path,
    mode: &str,
    tag: &str,
    stdout: &str,
    stderr: &str,
    wall_duration_ms: u64,
) {
    if output_json.exists() {
        return;
    }

    let combined = format!("{stdout}\n{stderr}");
    let duration_ms = parse_test_duration_ms(&combined).unwrap_or(wall_duration_ms);
    let summary = json!({
        "mode": mode,
        "tag": tag,
        "file_count": benchmark_file_count(mode),
        "duration_ms": duration_ms,
        "query": "where is auth flow handled",
        "limit": 20,
        "artifact_source": "benchmark_tools_semantic_fallback",
    });
    if let Ok(serialized) = serde_json::to_string(&summary) {
        let _ = fs::write(output_json, serialized);
    }
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
    use std::path::{Path, PathBuf};

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
    fn benchmark_file_count_matches_mode() {
        assert_eq!(super::benchmark_file_count("smoke"), 200);
        assert_eq!(super::benchmark_file_count("full"), 10_000);
    }

    #[test]
    fn parse_test_duration_reads_xcode_pass_line() {
        let output = "Test Case '-[CoderEngineTests.SemanticSearchBenchmarkTests testSemanticSearchBenchmarkSynthetic10kFiles]' passed (0.687 seconds).";
        assert_eq!(super::parse_test_duration_ms(output), Some(687));
    }

    #[test]
    fn write_benchmark_control_persists_mode_and_output_json() {
        let temp = std::env::temp_dir().join(format!(
            "semantic-benchmark-control-{}.json",
            std::process::id()
        ));
        let output_json = PathBuf::from("/tmp/semantic-benchmark.json");
        super::write_benchmark_control(&temp, "full", &output_json);
        let stored = std::fs::read_to_string(&temp).expect("control file");
        assert!(stored.contains("\"mode\":\"full\""));
        assert!(stored.contains("/tmp/semantic-benchmark.json"));
        let _ = std::fs::remove_file(temp);
    }

    #[test]
    fn repo_root_finds_semantic_benchmark_test() {
        let root = repo_root(Path::new("/Users/benjaminstoica/SoloCode")).expect("repo root");
        assert!(root.join("Tests/CoderEngineTests/SemanticSearch/SemanticSearchBenchmarkTests.swift").exists());
    }
}
