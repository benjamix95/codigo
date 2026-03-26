use crate::review_audit::helpers::{make_finding, make_result_standard, scoped_lines};
use serde_json::{json, Value};

pub(crate) fn run_bug_state_machine(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        let joined = lines.join("\n").to_lowercase();
        if !(joined.contains("enum") && joined.contains("state")) {
            continue;
        }
        let mutation_lines: Vec<(usize, &String)> = lines
            .iter()
            .enumerate()
            .filter(|(_, line)| {
                let lower = line.to_lowercase();
                lower.contains("state = .") || lower.contains(".state =")
            })
            .collect();
        if mutation_lines.len() >= 3
            && !joined.contains("switch state")
            && !joined.contains("guard state")
        {
            findings.push(make_finding(
                "suggestion",
                "regression",
                "audit_tool",
                &file,
                mutation_lines.first().map(|(i, _)| i + 1),
                "State machine con piu' mutazioni senza guard/switch espliciti.",
                "Rendi esplicite le transizioni di stato e aggiungi guardie o assert sui passaggi invalidi.",
                Some(0.67),
                Some(&format!("state mutations: {}", mutation_lines.len())),
                false,
                Some("audit_bug_state_machine".to_string()),
            ));
        }
    }

    Ok(make_result_standard(
        "audit_bug_state_machine",
        findings,
        true,
        "Nessuna anomalia evidente di state machine.",
        "Rilevate state transition sospette.",
        json!({"signal_type":"semantic","verification_hint":"Conferma le transizioni ammesse e cerca stati non protetti","promotion_gate":"strict_verified"}),
    ))
}

pub(crate) fn run_bug_api_contracts(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            let public_contract = lower.contains("public func")
                || lower.contains("open func")
                || lower.contains("protocol ");
            let stubbed = lower.contains("fatalerror(\"todo")
                || lower.contains("fatalerror(\"not implemented")
                || lower.contains("preconditionfailure(");
            if public_contract && stubbed {
                findings.push(make_finding(
                    "warning",
                    "correctness",
                    "bugHunter",
                    &file,
                    Some(index + 1),
                    "API o contratto pubblico con stub o failure esplicita nel path corrente.",
                    "Completa l'implementazione o limita la visibilità finché il contratto non è stabile.",
                    Some(0.83),
                    Some(line.trim()),
                    false,
                    Some("audit_bug_api_contracts".to_string()),
                ));
            }
        }
    }
    Ok(make_result_standard(
        "audit_bug_api_contracts",
        findings,
        true,
        "Nessun contract smell evidente nelle API scoped.",
        "Rilevati contract smell nelle API pubbliche o protocol.",
        json!({"signal_type":"semantic","verification_hint":"Conferma che lo stub sia realmente raggiungibile dal call graph o dal diff corrente","promotion_gate":"strict_verified"}),
    ))
}

pub(crate) fn run_bug_diff_risks(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let patterns: [(&str, &str, &str, &str, &str, f64, bool); 5] = [
        ("fatalError(", "critical", "regression", "fatalError in changed code can crash at runtime.", "Replace fatalError with recoverable error handling or an asserted precondition only in unreachable paths.", 0.90, true),
        ("try!", "warning", "correctness", "Force-try can turn recoverable failures into runtime crashes.", "Handle the throwing call explicitly and propagate or recover from the error.", 0.82, false),
        (" as! ", "warning", "correctness", "Forced cast introduces crash risk on unexpected input.", "Use a safe cast with graceful fallback or explicit validation.", 0.79, false),
        ("DispatchQueue.main.sync", "critical", "concurrency", "Synchronous dispatch to the main queue risks deadlock.", "Avoid synchronous main-queue dispatch and restructure the call flow.", 0.93, true),
        ("Thread.sleep(", "warning", "regression", "Thread.sleep in application code risks blocking and flaky timing.", "Use async waiting primitives or explicit scheduling instead of sleeping threads.", 0.77, false),
    ];
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            for (needle, sev, cat, msg, fix, conf, blocking) in patterns {
                if line.contains(needle) {
                    findings.push(make_finding(
                        sev,
                        cat,
                        "bugHunter",
                        &file,
                        Some(index + 1),
                        msg,
                        fix,
                        Some(conf),
                        Some(line.trim()),
                        blocking,
                        Some("audit_bug_diff_risks".to_string()),
                    ));
                }
            }
        }
    }
    Ok(make_result_standard(
        "audit_bug_diff_risks",
        findings,
        true,
        "No obvious crash or regression-risk patterns detected in scoped files.",
        "Detected bug-risk pattern(s) in scoped files.",
        json!({"signal_type":"pattern","verification_hint":"Conferma reachability in produzione","promotion_gate":"strict_verified"}),
    ))
}
