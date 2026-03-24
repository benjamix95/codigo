use app_core_protocol::mcp::CallToolResult;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::Path;
use std::process::Command;

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
    match Command::new(command).args(args).current_dir(cwd).output() {
        Ok(output) if output.status.success() || output.status.code() == Some(1) => {
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let text = if stdout.is_empty() { stderr } else { stdout };
            if text.is_empty() {
                CallToolResult::text("No results.")
            } else {
                CallToolResult::text(text)
            }
        }
        Ok(output) => {
            CallToolResult::error(String::from_utf8_lossy(&output.stderr).trim().to_string())
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
