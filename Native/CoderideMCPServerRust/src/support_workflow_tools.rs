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
        "coderide_export_debug_bundle" => Some(export_debug_bundle(workspace, arguments)),
        _ => None,
    }
}

/// Esegue test (Cargo, SwiftPM o progetto `.xcodeproj`). Timeout lungo: suite grandi.
fn run_tests(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let filter = string_arg(arguments, "filter");
    let scheme_arg = string_arg(arguments, "scheme");
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
    if let Some(proj) = first_xcodeproj(workspace) {
        let scheme = if !scheme_arg.is_empty() {
            scheme_arg
        } else if let Some(s) = xcodebuild_first_scheme(&proj) {
            s
        } else {
            proj.file_stem()
                .and_then(|x| x.to_str())
                .unwrap_or("App")
                .to_string()
        };
        let proj_arg = proj.to_string_lossy().into_owned();
        let mut args: Vec<String> = vec![
            "test".into(),
            "-project".into(),
            proj_arg,
            "-scheme".into(),
            scheme,
            "-destination".into(),
            "platform=macOS".into(),
        ];
        if !filter.is_empty() {
            args.push("-only-testing".into());
            args.push(filter);
        }
        let args_ref: Vec<&str> = args.iter().map(String::as_str).collect();
        return shell_output("xcodebuild", &args_ref, workspace, 900);
    }
    CallToolResult::text(
        json!({
            "ok": false,
            "error": "run_tests: serve Cargo.toml, Package.swift o un .xcodeproj nella root workspace.",
            "workspace": workspace.display().to_string(),
        })
        .to_string(),
    )
}

/// Primo scheme elencato da `xcodebuild -list` (stabile per la maggior parte dei progetti).
fn xcodebuild_first_scheme(xcodeproj: &Path) -> Option<String> {
    let out = Command::new("xcodebuild")
        .arg("-project")
        .arg(xcodeproj)
        .arg("-list")
        .output()
        .ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    let mut after_marker = false;
    for line in text.lines() {
        let s = line.trim();
        if s == "Schemes:" {
            after_marker = true;
            continue;
        }
        if after_marker && !s.is_empty() {
            return Some(s.to_string());
        }
    }
    None
}

fn first_xcodeproj(workspace: &Path) -> Option<PathBuf> {
    let entries = std::fs::read_dir(workspace).ok()?;
    let mut projects: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().and_then(|x| x.to_str()) == Some("xcodeproj"))
        .collect();
    if projects.is_empty() {
        return None;
    }
    projects.sort();
    projects.into_iter().next()
}

/// Fingerprint allineato a `AgentDebugSessionNDJSONLog` (Swift): path canonici ordinati, join `\u{1e}`.
fn agent_debug_bucket_key(primary_workspace: &Path, workspace_roots_csv: &str) -> String {
    let mut paths: Vec<PathBuf> = Vec::new();
    let trimmed = workspace_roots_csv.trim();
    if trimmed.is_empty() {
        paths.push(primary_workspace.to_path_buf());
    } else {
        for part in trimmed.split(',') {
            let p = part.trim();
            if p.is_empty() {
                continue;
            }
            let pbuf = PathBuf::from(p);
            let full = if pbuf.is_absolute() {
                pbuf
            } else {
                primary_workspace.join(pbuf)
            };
            paths.push(full);
        }
        if paths.is_empty() {
            paths.push(primary_workspace.to_path_buf());
        }
    }
    let mut canon: Vec<String> = paths
        .into_iter()
        .filter_map(|p| std::fs::canonicalize(&p).ok())
        .map(|p| p.to_string_lossy().to_string())
        .collect();
    canon.sort();
    let joined = canon.join("\x1e");
    format!("{:x}", Sha256::digest(joined.as_bytes()))
}

/// Crea uno zip del bucket NDJSON AgentDebug in Application Support (stesso fingerprint dell’app).
fn export_debug_bundle(workspace: &Path, arguments: &BTreeMap<String, Value>) -> CallToolResult {
    let home = match std::env::var("HOME") {
        Ok(h) if !h.is_empty() => h,
        _ => {
            return CallToolResult::error(
                "HOME non impostato: impossibile risolvere Application Support".to_string(),
            );
        }
    };
    let roots_csv = string_arg(arguments, "workspace_roots");
    let fp = agent_debug_bucket_key(workspace, &roots_csv);
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
