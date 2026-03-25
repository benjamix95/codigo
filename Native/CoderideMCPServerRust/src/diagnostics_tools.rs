use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::{Command, Output, Stdio};
#[cfg(unix)]
use std::os::unix::process::ExitStatusExt;

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_git_diff" => Some(git_diff(workspace, arguments)),
        "coderide_diagnostics" => Some(diagnostics(workspace, arguments)),
        "coderide_read_lints" => Some(read_lints(workspace)),
        "coderide_semantic_search" => Some(semantic_search(workspace, arguments)),
        _ => None,
    }
}

fn git_diff(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let scope = string_arg(arguments, "path");
    let args = if scope.is_empty() {
        vec!["diff", "--", "."]
    } else {
        vec!["diff", "--", scope.as_str()]
    };
    shell_text("git", &args, workspace)
}

fn diagnostics(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let manager = string_arg(arguments, "manager").to_lowercase();
    let (command, args): (&str, Vec<&str>) =
        if manager == "cargo" || workspace.join("Cargo.toml").exists() {
            ("cargo", vec!["check"])
        } else if workspace.join("Package.swift").exists() {
            ("swift", vec!["build"])
        } else if workspace.join("package.json").exists() {
            ("npm", vec!["run", "build"])
        } else {
            ("swift", vec!["build"])
        };
    shell_text(command, &args, workspace)
}

fn read_lints(workspace: &Path) -> CallToolResult {
    if workspace.join("Cargo.toml").exists() {
        return shell_text("cargo", &["check", "--message-format=short"], workspace);
    }
    if workspace.join("Package.swift").exists() {
        return shell_text("swift", &["build", "--build-tests"], workspace);
    }
    CallToolResult::error("No recognized linter found. Supported: Swift, Cargo.")
}

fn semantic_search(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let query = string_arg(arguments, "query");
    if query.is_empty() {
        return CallToolResult::error("Missing 'query' argument");
    }
    shell_text("rg", &["-n", "--no-heading", query.as_str()], workspace)
}

fn shell_text(command: &str, args: &[&str], cwd: &Path) -> CallToolResult {
    // Wrap in `timeout` (coreutils / macOS gtimeout fallback) to prevent hangs.
    let timeout_cmd = if Command::new("timeout").arg("--version").output().is_ok() {
        "timeout"
    } else {
        // macOS: try gtimeout from coreutils, otherwise run without timeout.
        "gtimeout"
    };
    let has_timeout = Command::new(timeout_cmd).arg("--version").output().is_ok();

    let output = if has_timeout {
        let mut full_args = vec!["120", command];
        full_args.extend(args.iter());
        Command::new(timeout_cmd)
            .args(&full_args)
            .current_dir(cwd)
            .output()
    } else {
        // Fallback: native Rust timeout via child.wait_with_output + thread.
        run_with_native_timeout(command, args, cwd, 120)
    };

    match output {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            // Exit code 124 = timeout killed the process.
            if output.status.code() == Some(124) {
                return CallToolResult::error(format!("{command} timed out after 120s"));
            }
            if output.status.success() || output.status.code() == Some(1) {
                let text = if stdout.is_empty() { stderr } else { stdout };
                if text.is_empty() {
                    CallToolResult::text("No results.")
                } else {
                    CallToolResult::text(text)
                }
            } else {
                CallToolResult::error(if stderr.is_empty() { stdout } else { stderr })
            }
        }
        Err(error) => CallToolResult::error(error.to_string()),
    }
}

fn string_arg(arguments: &BTreeMap<String, Value>, key: &str) -> String {
    arguments
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// Native Rust timeout: spawn child, wait on a thread, kill if exceeded.
fn run_with_native_timeout(
    command: &str,
    args: &[&str],
    cwd: &Path,
    timeout_secs: u64,
) -> std::io::Result<Output> {
    let mut child = Command::new(command)
        .args(args)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let timeout = std::time::Duration::from_secs(timeout_secs);
    let start = std::time::Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_status)) => return child.wait_with_output(),
            Ok(None) => {
                if start.elapsed() >= timeout {
                    // Kill and synthesize exit code 124 (same as coreutils timeout).
                    let _ = child.kill();
                    let _ = child.wait();
                    return Ok(Output {
                        status: std::process::ExitStatus::from_raw(124 << 8),
                        stdout: Vec::new(),
                        stderr: format!("{command} timed out after {timeout_secs}s")
                            .into_bytes(),
                    });
                }
                std::thread::sleep(std::time::Duration::from_millis(200));
            }
            Err(e) => return Err(e),
        }
    }
}
