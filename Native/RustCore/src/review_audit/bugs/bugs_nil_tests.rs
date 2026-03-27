use crate::review_audit::helpers::{
    make_finding, make_result_standard, scoped_lines, workspace_contains_file_named,
};
use regex::Regex;
use serde_json::{json, Value};
use std::path::PathBuf;

pub(crate) fn run_bug_nil_crash_paths(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    let re_force_unwrap =
        Regex::new(r"[A-Za-z0-9_)\]]!\s*(?:[\.,)\]\?:;]|$)").map_err(|e| format!("regex: {e}"))?;
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            if lower.contains("fatalerror(") {
                findings.push(make_finding(
                    "critical",
                    "correctness",
                    "audit_tool",
                    &file,
                    Some(index + 1),
                    "fatalError può crasher a runtime.",
                    "Sostituisci con gestione errori recuperabile o precondition solo su path non raggiungibili.",
                    Some(0.9),
                    Some(line.trim()),
                    true,
                    Some("audit_bug_nil_crash_paths".to_string()),
                ));
                continue;
            }
            if lower.contains("try!") {
                findings.push(make_finding(
                    "warning",
                    "correctness",
                    "audit_tool",
                    &file,
                    Some(index + 1),
                    "Possibile crash path da force-try.",
                    "Gestisci l'errore in modo esplicito.",
                    Some(0.84),
                    Some(line.trim()),
                    false,
                    Some("audit_bug_nil_crash_paths".to_string()),
                ));
                continue;
            }
            if lower.contains(" as! ") {
                findings.push(make_finding(
                    "warning",
                    "correctness",
                    "audit_tool",
                    &file,
                    Some(index + 1),
                    "Possibile crash path da cast forzato.",
                    "Usa cast sicuro e validazione dell'input.",
                    Some(0.79),
                    Some(line.trim()),
                    false,
                    Some("audit_bug_nil_crash_paths".to_string()),
                ));
                continue;
            }
            if lower.contains("first!") || lower.contains("last!") || re_force_unwrap.is_match(line)
            {
                findings.push(make_finding(
                    "warning",
                    "correctness",
                    "audit_tool",
                    &file,
                    Some(index + 1),
                    "Possibile crash path da force unwrap.",
                    "Sostituisci con guard/if let o fallback esplicito.",
                    Some(0.72),
                    Some(line.trim()),
                    false,
                    Some("audit_bug_nil_crash_paths".to_string()),
                ));
            }
        }
    }
    Ok(make_result_standard(
        "audit_bug_nil_crash_paths",
        findings,
        true,
        "Nessun nil/crash path rilevato.",
        "Rilevati possibili nil/crash path.",
        json!({"signal_type":"pattern","verification_hint":"Conferma reachability del path e input che lo attiva","promotion_gate":"strict_verified"}),
    ))
}

pub(crate) fn run_bug_test_impact(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        let lower = lines.join("\n").to_lowercase();
        if lower.contains("public struct")
            || lower.contains("public class")
            || lower.contains("public func")
        {
            findings.push(make_finding(
                "warning",
                "tests",
                "audit_tool",
                &file,
                None,
                "Public API changed without local test evidence.",
                "Aggiungi copertura di regressione o component test dedicati per il simbolo pubblico toccato.",
                Some(0.70),
                Some("public symbol without adjacent tests"),
                false,
                Some("audit_bug_test_impact".to_string()),
            ));
        }
    }
    Ok(make_result_standard(
        "audit_bug_test_impact",
        findings,
        true,
        "Nessun gap test evidente sui simboli pubblici.",
        "Rilevati possibili gap test su simboli pubblici.",
        json!({"signal_type":"test_derived","verification_hint":"Verifica la presenza di regression o component test effettivi per i simboli pubblici toccati","promotion_gate":"strict_verified"}),
    ))
}

pub(crate) fn run_bug_test_gaps(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let source_files: Vec<String> = scope_files
        .iter()
        .filter(|file| !file.to_lowercase().contains("test"))
        .cloned()
        .collect();
    if source_files.is_empty() {
        return Ok(make_result_standard(
            "audit_bug_test_gaps",
            vec![],
            !scope_files.is_empty(),
            "Nessun file sorgente non-test nello scope per il test-gap audit.",
            "Rilevati gap di test.",
            json!({"signal_type":"test_derived","verification_hint":"Conferma che i file sorgente modificati abbiano coverage mirata","promotion_gate":"strict_verified"}),
        ));
    }

    let scoped_lower = scope_files
        .iter()
        .map(|file| file.to_lowercase())
        .collect::<Vec<_>>();
    let mut findings = Vec::new();
    for file in source_files {
        let file_name = PathBuf::from(&file)
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or(file.as_str())
            .to_string();
        let stem = PathBuf::from(&file_name)
            .file_stem()
            .and_then(|name| name.to_str())
            .unwrap_or(file_name.as_str())
            .to_string();
        let candidate_names = vec![
            format!("{stem}Tests.swift"),
            format!("{stem}.test.ts"),
            format!("{stem}.spec.ts"),
            format!("test_{}.py", stem.to_lowercase()),
        ];
        let has_scoped_test = candidate_names.iter().any(|candidate| {
            let lower = candidate.to_lowercase();
            scoped_lower.iter().any(|path| {
                path == &lower
                    || path.ends_with(&format!("/{lower}"))
                    || path.ends_with(&format!("\\{lower}"))
            })
        });
        let has_workspace_test = candidate_names
            .iter()
            .any(|candidate| workspace_contains_file_named(workspace_path, candidate));
        if has_scoped_test || has_workspace_test {
            continue;
        }
        findings.push(make_finding(
            "suggestion",
            "tests",
            "audit_tool",
            &file,
            None,
            "Changed source file has no obvious paired test coverage.",
            "Add or update targeted tests covering the modified behavior and edge cases.",
            Some(0.66),
            Some(&format!("No matching test file found for {file_name}.")),
            false,
            Some("audit_bug_test_gaps".to_string()),
        ));
    }

    Ok(make_result_standard(
        "audit_bug_test_gaps",
        findings,
        true,
        "Nessun gap evidente di test coverage per i file nello scope.",
        "Rilevati possibili gap di test coverage.",
        json!({"signal_type":"test_derived","verification_hint":"Conferma che il comportamento modificato sia coperto da test mirati","promotion_gate":"strict_verified"}),
    ))
}
