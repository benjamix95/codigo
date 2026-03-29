use app_core_protocol::mcp::{CallToolResult, ToolContent};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_benchmark_indexing" => Some(run_indexing_benchmark(workspace, arguments)),
        "coderide_benchmark_review_pipeline" => Some(run_review_pipeline_benchmark(workspace, arguments)),
        _ => None,
    }
}

fn run_indexing_benchmark(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let phase = match required_phase(arguments) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let tag = optional_string(arguments, "tag").unwrap_or_else(default_timestamp_tag);
    let runs = optional_string(arguments, "runs");
    let warmup = optional_string(arguments, "warmup");
    let files = optional_string(arguments, "files");
    let root = match repo_root(workspace) {
        Ok(value) => value,
        Err(message) => return error(message),
    };
    let script = root.join("scripts/benchmark_indexing_pre_post.sh");

    let mut cmd = Command::new(&script);
    cmd.current_dir(&root);
    cmd.arg("--phase").arg(&phase);
    cmd.arg("--tag").arg(&tag);
    if let Some(value) = runs.as_deref() {
        cmd.arg("--runs").arg(value);
    }
    if let Some(value) = warmup.as_deref() {
        cmd.arg("--warmup").arg(value);
    }
    if let Some(value) = files.as_deref() {
        cmd.arg("--files").arg(value);
    }

    let output = match cmd.output() {
        Ok(value) => value,
        Err(err) => return error(format!("benchmark_indexing failed to launch: {err}")),
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return failure_with_structured(
            format!("benchmark_indexing failed (phase={phase}, tag={tag})"),
            json!({
                "tool": "benchmark_indexing",
                "phase": phase,
                "tag": tag,
                "status": "failed",
                "stdout": stdout,
                "stderr": stderr,
            }),
        );
    }

    let bench_dir = root.join("docs/benchmarks/indexing-hardening");
    let output_json = bench_dir.join(format!("{tag}-{phase}.json"));
    let log_file = bench_dir.join(format!("{tag}-{phase}.log"));
    let summary_md = bench_dir.join(format!("{tag}-summary.md"));

    success_with_structured(
        format!("benchmark_indexing {phase} {tag}"),
        json!({
            "tool": "benchmark_indexing",
            "phase": phase,
            "tag": tag,
            "status": "completed",
            "stdout": stdout,
            "stderr": stderr,
            "output_json": output_json.display().to_string(),
            "log_file": log_file.display().to_string(),
            "summary_md": summary_md.display().to_string(),
        }),
    )
}

fn run_review_pipeline_benchmark(
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> CallToolResult {
    let phase = match required_phase(arguments) {
        Ok(value) => value,
        Err(error) => return error,
    };
    let tag = optional_string(arguments, "tag").unwrap_or_else(|| "review-core-smoke".to_string());
    let root = match repo_root(workspace) {
        Ok(value) => value,
        Err(message) => return error(message),
    };
    let script = root.join("scripts/benchmark_review_pipeline_pre_post.sh");

    let output = match Command::new(&script)
        .current_dir(&root)
        .arg("--phase")
        .arg(&phase)
        .arg("--tag")
        .arg(&tag)
        .output()
    {
        Ok(value) => value,
        Err(err) => return error(format!("benchmark_review_pipeline failed to launch: {err}")),
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return failure_with_structured(
            format!("benchmark_review_pipeline failed (phase={phase}, tag={tag})"),
            json!({
                "tool": "benchmark_review_pipeline",
                "phase": phase,
                "tag": tag,
                "status": "failed",
                "stdout": stdout,
                "stderr": stderr,
            }),
        );
    }

    let out_dir = root.join("docs/benchmarks/review-core");
    let engine_json = out_dir.join(format!("{tag}-{phase}-engine.json"));
    let app_json = out_dir.join(format!("{tag}-{phase}-app.json"));
    let summary_md = out_dir.join(format!("{tag}-summary.md"));

    success_with_structured(
        format!("benchmark_review_pipeline {phase} {tag}"),
        json!({
            "tool": "benchmark_review_pipeline",
            "phase": phase,
            "tag": tag,
            "status": "completed",
            "stdout": stdout,
            "stderr": stderr,
            "engine_json": engine_json.display().to_string(),
            "app_json": app_json.display().to_string(),
            "summary_md": summary_md.display().to_string(),
        }),
    )
}

fn required_phase(arguments: &BTreeMap<String, Value>) -> Result<String, CallToolResult> {
    let phase = string_arg(arguments, "phase").to_lowercase();
    match phase.as_str() {
        "pre" | "post" => Ok(phase),
        _ => Err(error("Error: phase must be 'pre' or 'post'".to_string())),
    }
}

fn repo_root(workspace: &Path) -> Result<PathBuf, String> {
    let mut current = workspace.canonicalize().unwrap_or_else(|_| workspace.to_path_buf());
    loop {
        if current.join("scripts/benchmark_indexing_pre_post.sh").exists()
            && current.join("scripts/benchmark_review_pipeline_pre_post.sh").exists()
        {
            return Ok(current);
        }
        if !current.pop() {
            break;
        }
    }
    Err("Unable to locate repository root for benchmark scripts".to_string())
}

fn default_timestamp_tag() -> String {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(delta) => format!("benchmark-{}", delta.as_secs()),
        Err(_) => "benchmark-adhoc".to_string(),
    }
}

fn optional_string(arguments: &BTreeMap<String, Value>, key: &str) -> Option<String> {
    let value = string_arg(arguments, key);
    if value.trim().is_empty() {
        None
    } else {
        Some(value)
    }
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

fn error(message: impl Into<String>) -> CallToolResult {
    CallToolResult::error(message.into())
}

#[cfg(test)]
mod tests {
    use super::{repo_root, run_indexing_benchmark};
    use serde_json::{json, Value};
    use std::collections::BTreeMap;
    use std::path::Path;

    #[test]
    fn invalid_phase_fails_closed() {
        let mut args = BTreeMap::<String, Value>::new();
        args.insert("phase".to_string(), json!("adhoc"));
        let result = run_indexing_benchmark(Path::new("/Users/benjaminstoica/SoloCode"), &args);
        assert_eq!(result.is_error, Some(true));
    }

    #[test]
    fn repo_root_resolves_from_workspace() {
        let root = repo_root(Path::new("/Users/benjaminstoica/SoloCode")).expect("repo root");
        assert!(root.join("scripts/benchmark_indexing_pre_post.sh").exists());
        assert!(root.join("scripts/benchmark_review_pipeline_pre_post.sh").exists());
    }
}
