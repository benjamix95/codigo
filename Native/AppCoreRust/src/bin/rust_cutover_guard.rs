use app_core_protocol::app_core::{
    AppCoreRequest, AppCoreResponse, BoundaryAuditRequest, BoundaryAuditSummary,
};
use app_core_rust::{boundary::format_text_report, dispatch};
use std::collections::BTreeMap;
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
        legacy_non_ui_budget_by_prefix: split_budget_csv(&args.legacy_budget_prefixes)?,
        include_missing_candidate_files: args.include_missing_candidate_files,
    }))
    .map_err(|error| error.to_string())?;

    let AppCoreResponse::BoundaryAudit(report) = response;
    if args.format == "json" {
        println!(
            "{}",
            serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?
        );
    } else {
        println!("{}", format_text_report(&report));
    }

    Ok(exit_code_for_summary(
        &report.summary,
        args.fail_on_legacy_non_ui,
    ))
}

struct Args {
    workspace: String,
    allowlist: String,
    candidate_files: String,
    new_files: String,
    enforce_legacy_zero_prefixes: String,
    legacy_budget_prefixes: String,
    include_missing_candidate_files: bool,
    fail_on_legacy_non_ui: bool,
    format: String,
}

fn parse_args(args: Vec<String>) -> Result<Args, String> {
    let mut workspace = String::new();
    let mut allowlist = "Config/validation/rust-cutover-swift-allowlist.txt".to_string();
    let mut candidate_files = String::new();
    let mut new_files = String::new();
    let mut enforce_legacy_zero_prefixes = String::new();
    let mut legacy_budget_prefixes = String::new();
    let mut include_missing_candidate_files = false;
    let mut fail_on_legacy_non_ui = false;
    let mut format = "text".to_string();
    let mut index = 0usize;

    while index < args.len() {
        let key = &args[index];
        match key.as_str() {
            "--include-missing-candidate-files" => {
                include_missing_candidate_files = true;
                index += 1;
                continue;
            }
            "--fail-on-legacy-non-ui" => {
                fail_on_legacy_non_ui = true;
                index += 1;
                continue;
            }
            "--workspace" => workspace = args.get(index + 1).cloned().unwrap_or_default(),
            "--allowlist" => allowlist = args.get(index + 1).cloned().unwrap_or_default(),
            "--candidate-files" => {
                candidate_files = args.get(index + 1).cloned().unwrap_or_default()
            }
            "--new-files" => new_files = args.get(index + 1).cloned().unwrap_or_default(),
            "--enforce-legacy-zero-prefixes" => {
                enforce_legacy_zero_prefixes = args.get(index + 1).cloned().unwrap_or_default()
            }
            "--legacy-budget-prefixes" => {
                legacy_budget_prefixes = args.get(index + 1).cloned().unwrap_or_default()
            }
            "--format" => format = args.get(index + 1).cloned().unwrap_or_default(),
            other => {
                return Err(format!(
                    "Argomento sconosciuto per rust_cutover_guard: {other}"
                ))
            }
        }
        index += 2;
    }

    if workspace.is_empty() {
        return Err("Uso: rust_cutover_guard --workspace <path> [--allowlist <path>] [--candidate-files csv] [--new-files csv] [--enforce-legacy-zero-prefixes csv] [--legacy-budget-prefixes prefix=count;prefix=count] [--include-missing-candidate-files] [--fail-on-legacy-non-ui] [--format text|json]".to_string());
    }

    Ok(Args {
        workspace,
        allowlist,
        candidate_files,
        new_files,
        enforce_legacy_zero_prefixes,
        legacy_budget_prefixes,
        include_missing_candidate_files,
        fail_on_legacy_non_ui,
        format,
    })
}

fn exit_code_for_summary(summary: &BoundaryAuditSummary, fail_on_legacy_non_ui: bool) -> ExitCode {
    if summary.new_non_ui_files > 0
        || summary.budget_exceeded_legacy_non_ui_files > 0
        || (fail_on_legacy_non_ui && summary.legacy_non_ui_files > 0)
    {
        ExitCode::from(2)
    } else {
        ExitCode::SUCCESS
    }
}

fn split_csv(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn split_budget_csv(value: &str) -> Result<BTreeMap<String, usize>, String> {
    let mut output = BTreeMap::new();
    for item in value
        .split(';')
        .map(str::trim)
        .filter(|item| !item.is_empty())
    {
        let Some((prefix, budget)) = item.rsplit_once('=') else {
            return Err(format!("Formato budget non valido: {item}"));
        };
        let parsed_budget = budget
            .trim()
            .parse::<usize>()
            .map_err(|_| format!("Budget non valido per {prefix}: {budget}"))?;
        let normalized_prefix = prefix
            .trim()
            .trim_start_matches("./")
            .trim_end_matches('/')
            .to_string();
        if normalized_prefix.is_empty() {
            return Err(format!("Prefisso budget non valido: {item}"));
        }
        output.insert(normalized_prefix, parsed_budget);
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::{exit_code_for_summary, parse_args};
    use app_core_protocol::app_core::BoundaryAuditSummary;
    use std::process::ExitCode;

    #[test]
    fn parse_args_supports_fail_on_legacy_flag() {
        let args = parse_args(vec![
            "--workspace".to_string(),
            "/tmp/workspace".to_string(),
            "--fail-on-legacy-non-ui".to_string(),
        ])
        .expect("parse args");

        assert!(args.fail_on_legacy_non_ui);
    }

    #[test]
    fn exit_code_ignores_legacy_when_strict_flag_is_disabled() {
        let code = exit_code_for_summary(
            &BoundaryAuditSummary {
                legacy_non_ui_files: 3,
                ..BoundaryAuditSummary::default()
            },
            false,
        );

        assert_eq!(code, ExitCode::SUCCESS);
    }

    #[test]
    fn exit_code_fails_when_legacy_exists_in_strict_mode() {
        let code = exit_code_for_summary(
            &BoundaryAuditSummary {
                legacy_non_ui_files: 1,
                ..BoundaryAuditSummary::default()
            },
            true,
        );

        assert_eq!(code, ExitCode::from(2));
    }
}
