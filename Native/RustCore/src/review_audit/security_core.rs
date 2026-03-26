use super::helpers::{make_finding, make_result_standard, scoped_lines};
use serde_json::{json, Value};

pub(crate) fn run_security_dataflow(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
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
                findings.push(make_finding(
                    "critical",
                    "security",
                    "securityAuditor",
                    &file,
                    Some(index + 1),
                    "Possibile flusso input non validato verso sink sensibile.",
                    "Inserisci validazione/sanitizzazione esplicita tra source e sink o sostituisci il sink con un'alternativa sicura.",
                    Some(0.86),
                    Some(lines[index].trim()),
                    true,
                    Some("audit_security_dataflow".to_string()),
                ));
            }
        }
    }
    Ok(make_result_standard(
        "audit_security_dataflow",
        findings,
        coverage_available,
        "Nessun source->sink sospetto rilevato.",
        "Rilevati flow sospetti source->sink.",
        json!({"signal_type":"semantic","verification_hint":"Conferma che source e sink appartengano allo stesso flow runtime","promotion_gate":"strict_verified","behavioral_impact":"potential_remote_exploit"}),
    ))
}

pub(crate) fn run_security_authz(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
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
            findings.push(make_finding(
                "warning",
                "security",
                "securityAuditor",
                &file,
                None,
                "Surface applicativa con handler/route senza segnali evidenti di authz.",
                "Verifica che i path sensibili siano protetti da middleware, permessi o session guards espliciti.",
                Some(0.68),
                Some("route-like handlers found without authz markers"),
                false,
                Some("audit_security_authz".to_string()),
            ));
        }
    }
    Ok(make_result_standard(
        "audit_security_authz",
        findings,
        true,
        "Nessun gap di authz evidente nei file scoped.",
        "Rilevati potenziali gap di authz.",
        json!({"signal_type":"semantic","verification_hint":"Confronta i path segnalati con middleware e controlli di ruolo reali","promotion_gate":"strict_verified"}),
    ))
}
