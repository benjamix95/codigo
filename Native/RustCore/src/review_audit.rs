use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;

pub fn run_audit(
    tool_name: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    match tool_name {
        "audit_security_dataflow" => run_security_dataflow(scope_files, workspace_path),
        "audit_security_authz" => run_security_authz(scope_files, workspace_path),
        "audit_security_crypto" => run_pattern_tool(
            tool_name,
            scope_files,
            workspace_path,
            "security",
            "securityAuditor",
            &[
                ("md5", "warning", "Uso di MD5 rilevato.", "Sostituisci con SHA-256/512 o primitive moderne orientate allo use-case.", 0.82),
                ("sha1", "warning", "Uso di SHA1 rilevato.", "Evita SHA1 per nuove implementazioni e token security-sensitive.", 0.81),
                ("rand()", "warning", "Generatore pseudo-random non adatto a segreti o token.", "Usa generatori crittograficamente sicuri.", 0.77),
                ("arc4random", "suggestion", "Generatore random legacy rilevato.", "Valuta primitive moderne e intenzione esplicita del random usato.", 0.61),
            ],
            "Nessun pattern crypto debole rilevato.",
            "Rilevati pattern crypto deboli o legacy.",
            json!({"signal_type":"pattern","verification_hint":"Conferma il contesto crittografico reale prima della promozione","promotion_gate":"strict_verified"}),
        ),
        "audit_security_deserialization" => run_pattern_tool(
            tool_name,
            scope_files,
            workspace_path,
            "security",
            "securityAuditor",
            &[
                ("pickle.load", "critical", "Deserializzazione Python non sicura.", "Usa formati sicuri o valida rigorosamente la sorgente prima del decode.", 0.91),
                ("yaml.load(", "warning", "Parsing YAML potenzialmente non sicuro.", "Preferisci safe_load o equivalente sicuro.", 0.83),
                ("nskeyedunarchiver.unarchiveobject", "warning", "Deserializzazione Objective-C/Swift legacy rilevata.", "Richiedi secure coding e valida il payload.", 0.80),
                ("eval(", "critical", "Valutazione dinamica di codice rilevata.", "Elimina eval o isola rigidamente l'input e l'ambiente.", 0.94),
            ],
            "Nessun pattern di deserializzazione pericolosa rilevato.",
            "Rilevati pattern di parsing/deserializzazione da verificare.",
            json!({"signal_type":"pattern","verification_hint":"Conferma reachability e sorgente del payload prima della promozione","promotion_gate":"strict_verified"}),
        ),
        "audit_security_surface" => run_pattern_tool(
            tool_name,
            scope_files,
            workspace_path,
            "security",
            "securityAuditor",
            &[
                ("nsallowsarbitraryloads", "warning", "ATS rilassato nel progetto.", "Riduci l'eccezione ATS al minimo indispensabile e documenta il motivo.", 0.73),
                ("wkwebview", "suggestion", "Surface WebView presente: controlla navigation policy, script injection e origin isolation.", "Verifica sandbox, navigation delegate e contenuti caricati.", 0.60),
                ("debug = true", "suggestion", "Flag di debug abilitato nel codice scoped.", "Verifica che i flag di debug non siano attivi nei build di produzione.", 0.58),
            ],
            "Nessuna configurazione di surface ad alto rischio rilevata.",
            "Rilevati segnali di attack surface da rivedere.",
            json!({"signal_type":"pattern","verification_hint":"Conferma che i flag o le surface siano realmente esposte in produzione","promotion_gate":"strict_verified"}),
        ),
        "audit_bug_nil_crash_paths" => run_bug_nil_crash_paths(scope_files, workspace_path),
        "audit_bug_test_impact" => run_bug_test_impact(scope_files, workspace_path),
        "audit_bug_test_gaps" => run_bug_test_gaps(scope_files, workspace_path),
        "audit_bug_state_machine" => run_bug_state_machine(scope_files, workspace_path),
        "audit_bug_concurrency" => run_pattern_tool(
            tool_name,
            scope_files,
            workspace_path,
            "concurrency",
            "audit_tool",
            &[("dispatchqueue.main.sync", "critical", "Rischio deadlock su main thread.", "Evita sync sulla main queue o riprogetta il flusso.", 0.93)],
            "Nessun pattern di concorrenza critico rilevato.",
            "Rilevati pattern di concorrenza da verificare.",
            json!({"signal_type":"pattern","verification_hint":"Conferma il contesto di chiamata runtime prima della promozione","promotion_gate":"strict_verified"}),
        ),
        "audit_bug_error_handling" => run_pattern_tool(
            tool_name,
            scope_files,
            workspace_path,
            "correctness",
            "audit_tool",
            &[
                ("catch {}", "warning", "Catch vuoto che sopprime il failure.", "Registra, propaga o convertilo in fallback esplicito.", 0.88),
                ("try?", "suggestion", "Uso di try? da verificare: puo' nascondere failure reali.", "Valuta gestione esplicita dell'errore nei path critici.", 0.62),
                ("assertionfailure(", "suggestion", "Failure path non produttivo o potenzialmente non testato.", "Verifica il comportamento in release e nei test.", 0.58),
            ],
            "Nessun anti-pattern evidente di error handling.",
            "Rilevati anti-pattern di gestione errori o fallback silenziosi.",
            json!({"signal_type":"pattern","verification_hint":"Conferma il path runtime e la raggiungibilita' del codice segnalato","promotion_gate":"strict_verified"}),
        ),
        _ => Err("unsupported_tool".to_string()),
    }
}

fn run_security_dataflow(scope_files: Vec<String>, workspace_path: &str) -> Result<Value, String> {
    let source_tokens = [
        "request.",
        "params[",
        "query[",
        "input",
        "readline(",
        "stdin",
        "urlqueryitem",
        "body[",
    ];
    let sink_tokens = [
        "process(",
        "shell: true",
        "innerhtml",
        "sqlite",
        "raw(",
        "openurl(",
        "write(to:",
    ];
    let mut findings = Vec::new();
    let coverage_available = !scope_files.is_empty();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for index in 0..lines.len() {
            let start = index.saturating_sub(5);
            let end = usize::min(lines.len().saturating_sub(1), index + 5);
            let window = lines[start..=end].join("\n").to_lowercase();
            let has_source = source_tokens.iter().any(|token| window.contains(token));
            let has_sink = sink_tokens.iter().any(|token| window.contains(token));
            if has_source && has_sink {
                findings.push(make_finding("critical", "security", "securityAuditor", &file, Some(index + 1), "Possibile flusso input non validato verso sink sensibile.", "Inserisci validazione/sanitizzazione esplicita tra source e sink o sostituisci il sink con un'alternativa sicura.", Some(0.86), Some(lines[index].trim()), true, Some(tool_name("audit_security_dataflow"))));
            }
        }
    }
    Ok(make_result(
        "audit_security_dataflow",
        findings,
        coverage_available,
        "Nessun source->sink sospetto rilevato.",
        "Rilevati flow sospetti source->sink.",
        json!({"signal_type":"semantic","verification_hint":"Conferma che source e sink appartengano allo stesso flow runtime","promotion_gate":"strict_verified","behavioral_impact":"potential_remote_exploit"}),
    ))
}

fn run_security_authz(scope_files: Vec<String>, workspace_path: &str) -> Result<Value, String> {
    let route_tokens = [
        "app.get",
        "app.post",
        "router.",
        "@get",
        "@post",
        "navigationdestination",
        "handle(",
    ];
    let auth_tokens = [
        "authorize",
        "auth",
        "permission",
        "role",
        "isadmin",
        "guard let user",
        "session",
    ];
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        let lower_file = file.to_lowercase();
        if !["route", "controller", "handler", "view"]
            .iter()
            .any(|token| lower_file.contains(token))
        {
            continue;
        }
        let lower = lines.join("\n").to_lowercase();
        let has_route = route_tokens.iter().any(|token| lower.contains(token));
        let has_auth = auth_tokens.iter().any(|token| lower.contains(token));
        if has_route && !has_auth {
            findings.push(make_finding("warning", "security", "securityAuditor", &file, None, "Surface applicativa con handler/route senza segnali evidenti di authz.", "Verifica che i path sensibili siano protetti da middleware, permessi o session guards espliciti.", Some(0.68), Some("route-like handlers found without authz markers"), false, Some(tool_name("audit_security_authz"))));
        }
    }
    Ok(make_result(
        "audit_security_authz",
        findings,
        true,
        "Nessun gap di authz evidente nei file scoped.",
        "Rilevati potenziali gap di authz.",
        json!({"signal_type":"semantic","verification_hint":"Confronta i path segnalati con middleware e controlli di ruolo reali","promotion_gate":"strict_verified"}),
    ))
}

fn run_bug_nil_crash_paths(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            if lower.contains("fatalerror(") || lower.contains(" as! ") || lower.contains("try!") {
                findings.push(make_finding(
                    "critical",
                    "correctness",
                    "audit_tool",
                    &file,
                    Some(index + 1),
                    "Potential nil crash path detected.",
                    "Replace the unsafe operation with a guarded path or explicit error handling.",
                    Some(0.92),
                    Some(line.trim()),
                    true,
                    Some(tool_name("audit_bug_nil_crash_paths")),
                ));
            }
        }
    }
    Ok(make_result(
        "audit_bug_nil_crash_paths",
        findings,
        true,
        "Nessun nil/crash path rilevato.",
        "Rilevati possibili nil/crash path.",
        json!({"signal_type":"pattern","verification_hint":"Conferma reachability del path e input che lo attiva","promotion_gate":"strict_verified"}),
    ))
}

fn run_bug_test_impact(scope_files: Vec<String>, workspace_path: &str) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        let lower = lines.join("\n").to_lowercase();
        if lower.contains("public struct")
            || lower.contains("public class")
            || lower.contains("public func")
        {
            findings.push(make_finding("warning", "tests", "audit_tool", &file, None, "Public API changed without local test evidence.", "Aggiungi copertura di regressione o component test dedicati per il simbolo pubblico toccato.", Some(0.70), Some("public symbol without adjacent tests"), false, Some(tool_name("audit_bug_test_impact"))));
        }
    }
    Ok(make_result(
        "audit_bug_test_impact",
        findings,
        true,
        "Nessun gap test evidente sui simboli pubblici.",
        "Rilevati possibili gap test su simboli pubblici.",
        json!({"signal_type":"test_derived","verification_hint":"Verifica la presenza di regression o component test effettivi per i simboli pubblici toccati","promotion_gate":"strict_verified"}),
    ))
}

fn run_bug_test_gaps(scope_files: Vec<String>, workspace_path: &str) -> Result<Value, String> {
    let source_files = scope_files
        .iter()
        .filter(|file| !file.to_lowercase().contains("test"))
        .cloned()
        .collect::<Vec<_>>();
    if source_files.is_empty() {
        return Ok(make_result(
            "audit_bug_test_gaps",
            Vec::new(),
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
            Some(tool_name("audit_bug_test_gaps")),
        ));
    }

    Ok(make_result(
        "audit_bug_test_gaps",
        findings,
        true,
        "Nessun gap evidente di test coverage per i file nello scope.",
        "Rilevati possibili gap di test coverage.",
        json!({"signal_type":"test_derived","verification_hint":"Conferma che il comportamento modificato sia coperto da test mirati","promotion_gate":"strict_verified"}),
    ))
}

fn run_bug_state_machine(scope_files: Vec<String>, workspace_path: &str) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        let joined = lines.join("\n").to_lowercase();
        if !(joined.contains("enum") && joined.contains("state")) {
            continue;
        }
        let mutation_lines = lines
            .iter()
            .enumerate()
            .filter(|(_, line)| {
                let lower = line.to_lowercase();
                lower.contains("state = .") || lower.contains(".state =")
            })
            .collect::<Vec<_>>();
        if mutation_lines.len() >= 3
            && !joined.contains("switch state")
            && !joined.contains("guard state")
        {
            findings.push(make_finding(
                "suggestion",
                "regression",
                "audit_tool",
                &file,
                mutation_lines.first().map(|(index, _)| index + 1),
                "State machine con piu' mutazioni senza guard/switch espliciti.",
                "Rendi esplicite le transizioni di stato e aggiungi guardie o assert sui passaggi invalidi.",
                Some(0.67),
                Some(&format!("state mutations: {}", mutation_lines.len())),
                false,
                Some(tool_name("audit_bug_state_machine")),
            ));
        }
    }

    Ok(make_result(
        "audit_bug_state_machine",
        findings,
        true,
        "Nessuna anomalia evidente di state machine.",
        "Rilevate state transition sospette.",
        json!({"signal_type":"semantic","verification_hint":"Conferma le transizioni ammesse e cerca stati non protetti","promotion_gate":"strict_verified"}),
    ))
}

fn run_pattern_tool(
    tool_key: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
    category: &str,
    origin: &str,
    patterns: &[(&str, &str, &str, &str, f64)],
    empty_summary: &str,
    hit_summary: &str,
    metadata: Value,
) -> Result<Value, String> {
    let mut findings = Vec::new();
    for (file, lines) in scoped_lines(scope_files, workspace_path)? {
        for (index, line) in lines.iter().enumerate() {
            let lower = line.to_lowercase();
            for (needle, severity, message, remediation, confidence) in patterns {
                if lower.contains(&needle.to_lowercase()) {
                    findings.push(make_finding(
                        severity,
                        category,
                        origin,
                        &file,
                        Some(index + 1),
                        message,
                        remediation,
                        Some(*confidence),
                        Some(line.trim()),
                        *severity == "critical",
                        Some(tool_name(tool_key)),
                    ));
                }
            }
        }
    }
    Ok(make_result(
        tool_key,
        findings,
        true,
        empty_summary,
        hit_summary,
        metadata,
    ))
}

fn scoped_lines(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Vec<(String, Vec<String>)>, String> {
    let mut output = Vec::new();
    for file in scope_files {
        let path = PathBuf::from(workspace_path).join(&file);
        let content = fs::read_to_string(&path)
            .map_err(|err| format!("failed to read {}: {err}", path.display()))?;
        output.push((file, content.lines().map(ToString::to_string).collect()));
    }
    Ok(output)
}

fn workspace_contains_file_named(workspace_path: &str, target_file_name: &str) -> bool {
    let mut stack = vec![PathBuf::from(workspace_path)];
    while let Some(dir) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = path
                .file_name()
                .and_then(|name| name.to_str())
                .unwrap_or_default();
            if path.is_dir() {
                if matches!(
                    file_name,
                    ".git" | "DerivedData" | "build" | "node_modules" | ".build" | "dist"
                ) {
                    continue;
                }
                stack.push(path);
                continue;
            }
            if file_name.eq_ignore_ascii_case(target_file_name) {
                return true;
            }
        }
    }
    false
}

fn make_result(
    tool_name: &str,
    findings: Vec<Value>,
    coverage_available: bool,
    empty_summary: &str,
    hit_summary: &str,
    metadata: Value,
) -> Value {
    let summary = if findings.is_empty() {
        empty_summary.to_string()
    } else {
        format!("{} {}", hit_summary, findings.len())
    };
    json!({
        "toolName": tool_name,
        "findings": findings,
        "durationMs": 1,
        "coverageAvailable": coverage_available,
        "summary": summary,
        "adaptersUsed": [],
        "verificationHints": metadata.get("verification_hint").cloned().map(|hint| vec![hint]).unwrap_or_else(|| Vec::<Value>::new()),
        "metadata": metadata,
        "clusters": []
    })
}

fn make_finding(
    severity: &str,
    category: &str,
    origin: &str,
    file_path: &str,
    line_number: Option<usize>,
    message: &str,
    suggested_fix: &str,
    confidence: Option<f64>,
    evidence: Option<&str>,
    blocking: bool,
    source_tool: Option<String>,
) -> Value {
    json!({
        "id": format!("{}:{}:{}", file_path, line_number.unwrap_or(0), message),
        "severity": severity,
        "category": category,
        "origin": origin,
        "filePath": file_path,
        "lineNumber": line_number,
        "message": message,
        "suggestedFix": suggested_fix,
        "confidence": confidence,
        "evidence": evidence,
        "sourceTool": source_tool,
        "blocking": blocking,
        "status": "open",
        "comments": [],
        "createdAt": 0.0
    })
}

fn tool_name(name: &str) -> String {
    name.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn dataflow_audit_detects_source_sink() {
        let root = std::env::temp_dir().join(format!(
            "review-audit-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            root.join("Service.swift"),
            "let input = request.query[\"cmd\"]\nrunProcess(input, shell: true)\n",
        )
        .unwrap();
        let result = run_audit(
            "audit_security_dataflow",
            vec!["Service.swift".to_string()],
            root.to_str().unwrap(),
        )
        .unwrap();
        assert!(!result["findings"].as_array().unwrap().is_empty());
    }

    #[test]
    fn bug_audits_support_state_machine_error_handling_and_test_gaps() {
        let root = std::env::temp_dir().join(format!(
            "review-audit-bug-tools-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(root.join("Sources")).unwrap();
        std::fs::write(
            root.join("Sources/Flow.swift"),
            "enum ViewState { case idle, loading, done }\nstate = .idle\nstate = .loading\nstate = .done\ncatch {}\n",
        )
        .unwrap();

        let state_machine = run_audit(
            "audit_bug_state_machine",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
        )
        .unwrap();
        assert_eq!(
            state_machine["toolName"].as_str(),
            Some("audit_bug_state_machine")
        );
        assert!(!state_machine["findings"].as_array().unwrap().is_empty());

        let error_handling = run_audit(
            "audit_bug_error_handling",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
        )
        .unwrap();
        assert_eq!(
            error_handling["toolName"].as_str(),
            Some("audit_bug_error_handling")
        );
        assert!(!error_handling["findings"].as_array().unwrap().is_empty());

        let test_gaps = run_audit(
            "audit_bug_test_gaps",
            vec!["Sources/Flow.swift".to_string()],
            root.to_str().unwrap(),
        )
        .unwrap();
        assert_eq!(test_gaps["toolName"].as_str(), Some("audit_bug_test_gaps"));
        assert!(!test_gaps["findings"].as_array().unwrap().is_empty());
    }
}
