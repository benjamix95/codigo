use app_core_protocol::mcp::CallToolResult;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::search_tools::string_arg;
use serde_json::Value;

pub fn supports(name: &str) -> bool {
    matches!(name, "coderide_run_tests" | "coderide_export_debug_bundle")
}

pub fn handle(
    name: &str,
    workspace: &Path,
    arguments: &BTreeMap<String, Value>,
) -> Option<CallToolResult> {
    match name {
        "coderide_run_tests" => Some(run_tests(workspace, arguments)),
        "coderide_export_debug_bundle" => Some(export_debug_bundle(workspace)),
        _ => None,
    }
}

/// Esegue test (Cargo o SwiftPM). Timeout lungo: suite grandi.
fn run_tests(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let filter = string_arg(arguments, "filter");
    if workspace.join("Cargo.toml").is_file() {
        if filter.is_empty() {
            return shell_output("cargo", &["test"], workspace, 600);
        }
        return shell_output("cargo", &["test", filter.as_str()], workspace, 600);
    }
    if workspace.join("Package.swift").is_file() {
        if filter.is_empty() {
            return shell_output("swift", &["test"], workspace, 600);
        }
        return shell_output("swift", &["test", "--filter", filter.as_str()], workspace, 600);
    }
    CallToolResult::text(
        json!({
            "ok": false,
            "error": "run_tests supports only Cargo or SwiftPM workspaces (Cargo.toml / Package.swift).",
            "workspace": workspace.display().to_string(),
        })
        .to_string(),
    )
}

/// Crea uno zip del bucket NDJSON AgentDebug in Application Support (stesso fingerprint dell’app).
fn export_debug_bundle(workspace: &Path) -> CallToolResult {
    let home = match std::env::var("HOME") {
        Ok(h) if !h.is_empty() => h,
        _ => {
            return CallToolResult::error(
                "HOME non impostato: impossibile risolvere Application Support".to_string(),
            );
        }
    };
    let canon = std::fs::canonicalize(workspace).unwrap_or_else(|_| workspace.to_path_buf());
    let mut hasher = Sha256::new();
    hasher.update(canon.to_string_lossy().as_bytes());
    let fp = format!("{:x}", hasher.finalize());
    let ndjson_dir = PathBuf::from(home)
        .join("Library/Application Support/SoloCode/AgentDebugNDJSON")
        .join(&fp);
    if !ndjson_dir.is_dir() {
        return CallToolResult::text(
            json!({
                "ok": false,
                "detail": "Nessun bucket NDJSON trovato per questo workspace. Apri il progetto nell’app e riprova.",
                "expected_dir": ndjson_dir.display().to_string(),
            })
            .to_string(),
        );
    }
    let out_dir = workspace.join(".solocode");
    if let Err(e) = std::fs::create_dir_all(&out_dir) {
        return CallToolResult::error(format!(".solocode: {e}"));
    }
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let zip_name = format!("debug-support-bundle-{ts}.zip");
    let zip_path = out_dir.join(&zip_name);
    let stat = Command::new("/usr/bin/zip")
        .args(["-r", "-q", zip_path.to_string_lossy().as_ref(), "."])
        .current_dir(&ndjson_dir)
        .status();
    match stat {
        Ok(s) if s.success() => CallToolResult::text(
            json!({
                "ok": true,
                "zip_path": zip_path.display().to_string(),
                "source_dir": ndjson_dir.display().to_string(),
            })
            .to_string(),
        ),
        Ok(s) => CallToolResult::error(format!(
            "zip terminato con stato {:?}",
            s.code()
        )),
        Err(e) => CallToolResult::error(format!(
            "zip non eseguito (installare zip di sistema o usare macOS): {e}"
        )),
    }
}

fn shell_output(cmd: &str, args: &[&str], cwd: &Path, timeout_secs: u64) -> CallToolResult {
    match run_with_timeout(cmd, args, cwd, timeout_secs) {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let stderr = String::from_utf8_lossy(&output.stderr);
            let exit = output.status.code().unwrap_or(-1);
            let combined = if stdout.trim().is_empty() {
                stderr.trim().to_string()
            } else {
                stdout.trim().to_string()
            };
            CallToolResult::text(
                json!({
                    "command": cmd,
                    "args": args,
                    "exit_code": exit,
                    "ok": output.status.success(),
                    "output_tail": combined.chars().rev().take(24_000).collect::<String>().chars().rev().collect::<String>(),
                })
                .to_string(),
            )
        }
        Err(e) => CallToolResult::error(e),
    }
}

fn run_with_timeout(
    command: &str,
    args: &[&str],
    cwd: &Path,
    timeout_secs: u64,
) -> Result<Output, String> {
    let mut child = Command::new(command)
        .args(args)
        .current_dir(cwd)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("spawn {command}: {e}"))?;
    let timeout = std::time::Duration::from_secs(timeout_secs);
    let start = std::time::Instant::now();
    loop {
        match child.try_wait().map_err(|e| e.to_string())? {
            Some(_) => return child.wait_with_output().map_err(|e| e.to_string()),
            None => {
                if start.elapsed() >= timeout {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("{command} timed out after {}s", timeout_secs));
                }
                std::thread::sleep(std::time::Duration::from_millis(20));
            }
        }
    }
}
