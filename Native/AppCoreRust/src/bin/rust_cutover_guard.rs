use app_core_protocol::app_core::{AppCoreRequest, AppCoreResponse, BoundaryAuditRequest};
use app_core_rust::{dispatch, boundary::format_text_report};
use std::env;
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<ExitCode, String> {
    let args = parse_args(env::args().skip(1).collect())?;
    let response = dispatch(AppCoreRequest::BoundaryAudit(BoundaryAuditRequest {
        workspace_root: args.workspace,
        allowlist_path: args.allowlist,
        candidate_files: split_csv(&args.candidate_files),
        new_files: split_csv(&args.new_files),
        enforce_legacy_zero_prefixes: split_csv(&args.enforce_legacy_zero_prefixes),
    }))
    .map_err(|error| error.to_string())?;

    let AppCoreResponse::BoundaryAudit(report) = response;
    if args.format == "json" {
        println!("{}", serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?);
    } else {
        println!("{}", format_text_report(&report));
    }

    Ok(if report.summary.new_non_ui_files > 0 || report.summary.enforced_legacy_non_ui_files > 0 {
        ExitCode::from(2)
    } else {
        ExitCode::SUCCESS
    })
}

struct Args {
    workspace: String,
    allowlist: String,
    candidate_files: String,
    new_files: String,
    enforce_legacy_zero_prefixes: String,
    format: String,
}

fn parse_args(args: Vec<String>) -> Result<Args, String> {
    let mut workspace = String::new();
    let mut allowlist = "Config/validation/rust-cutover-swift-allowlist.txt".to_string();
    let mut candidate_files = String::new();
    let mut new_files = String::new();
    let mut enforce_legacy_zero_prefixes = String::new();
    let mut format = "text".to_string();
    let mut index = 0usize;

    while index < args.len() {
        let key = &args[index];
        let value = args.get(index + 1).cloned().unwrap_or_default();
        match key.as_str() {
            "--workspace" => workspace = value,
            "--allowlist" => allowlist = value,
            "--candidate-files" => candidate_files = value,
            "--new-files" => new_files = value,
            "--enforce-legacy-zero-prefixes" => enforce_legacy_zero_prefixes = value,
            "--format" => format = value,
            other => return Err(format!("Argomento sconosciuto per rust_cutover_guard: {other}")),
        }
        index += 2;
    }

    if workspace.is_empty() {
        return Err("Uso: rust_cutover_guard --workspace <path> [--allowlist <path>] [--candidate-files csv] [--new-files csv] [--enforce-legacy-zero-prefixes csv] [--format text|json]".to_string());
    }

    Ok(Args {
        workspace,
        allowlist,
        candidate_files,
        new_files,
        enforce_legacy_zero_prefixes,
        format,
    })
}

fn split_csv(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(ToString::to_string)
        .collect()
}
