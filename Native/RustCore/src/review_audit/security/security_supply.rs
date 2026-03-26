use crate::review_audit::helpers::{make_finding, pack_payload, run_pattern_tool};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::path::PathBuf;
use std::process::Command;

pub(crate) fn run_security_secrets(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    run_pattern_tool(
        "audit_security_secrets",
        scope_files,
        workspace_path,
        "security",
        "securityAuditor",
        &[
            ("api_key", "critical", "Possibile API key hardcoded.", "Sposta i segreti in variabili d'ambiente, keychain o vault; ruota la chiave esposta.", 0.9),
            ("apikey", "warning", "Stringa 'apikey' rilevata: verifica che non sia un segreto committato.", "Usa configurazione esterna e mai commit di segreti.", 0.72),
            ("secret=", "warning", "Assegnazione a 'secret' nel codice.", "Verifica che non sia un segreto reale; preferisci secret manager.", 0.7),
            ("password=", "warning", "Possibile password in chiaro nel codice.", "Rimuovi credenziali dal repo; usa auth sicura.", 0.78),
            ("bearer ", "warning", "Token Bearer in sorgente.", "Non committare token; usa header runtime o vault.", 0.75),
            ("private_key", "critical", "Possibile chiave privata nel repository.", "Rimuovi e ruota; usa PEM da path sicuro fuori dal VCS.", 0.93),
            ("aws_secret", "critical", "Credenziale AWS-style rilevata.", "Ruota credenziali e usa IAM ruoli / secrets manager.", 0.91),
            ("-----begin", "critical", "Blocco PEM/chiave in file sorgente.", "Non versionare chiavi; sposta in gestore segreti.", 0.94),
            ("sk_live_", "critical", "Stripe live secret pattern.", "Ruota la chiave; solo env sicuro.", 0.95),
            ("aiza", "warning", "Possibile Google API key (AIza).", "Ruota e restringi key; non in repo.", 0.8),
        ],
        "Nessun pattern di segreto ovvio rilevato.",
        "Rilevati pattern che possono indicare segreti hardcoded.",
        json!({"signal_type":"pattern","verification_hint":"Conferma falsi positivi (es. placeholder) prima della promozione","promotion_gate":"strict_verified"}),
    )
}

pub(crate) fn run_security_patterns(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    run_pattern_tool(
        "audit_security_patterns",
        scope_files,
        workspace_path,
        "security",
        "securityAuditor",
        &[
            ("disable_ssl", "warning", "SSL verificato disabilitato o simile.", "Abilita certificate pinning / validazione TLS.", 0.82),
            ("allowsinvalidssl", "warning", "Invalid SSL consentito.", "Rimuovi in produzione.", 0.85),
            ("http://127.0.0.1", "suggestion", "HTTP verso localhost in codice.", "OK in dev; verifica non sia usato in release.", 0.55),
            (" md5(", "warning", "MD5 per hash generico.", "Usa SHA-256+ per integrità security-sensitive.", 0.68),
            ("exec(", "warning", "exec/eval dinamico potenzialmente pericoloso.", "Valida input e limita superficie.", 0.74),
            ("sqlite3_exec", "suggestion", "Raw SQLite C API: rischio SQL injection se string concatenation.", "Usa query parametrizzate.", 0.63),
            ("print(", "suggestion", "Logging potenziale di dati sensibili (contesto).", "Evita PII in log produzione.", 0.52),
        ],
        "Nessun pattern di policy security ovvia.",
        "Rilevati pattern di policy/insecure usage da verificare.",
        json!({"signal_type":"pattern","verification_hint":"Conferma contesto (dev vs prod) prima della promozione","promotion_gate":"strict_verified"}),
    )
}

pub(crate) fn run_security_dependencies(workspace_path: &str) -> Result<Value, String> {
    let managers: [(&str, &[&str]); 3] = [
        ("package-lock.json", &["npm", "audit", "--json"]),
        ("pnpm-lock.yaml", &["pnpm", "audit", "--json"]),
        ("yarn.lock", &["yarn", "audit", "--json"]),
    ];
    for (manifest, args) in managers {
        let manifest_path = PathBuf::from(workspace_path).join(manifest);
        if !manifest_path.is_file() {
            continue;
        }
        let label = args[0];
        let output = Command::new("/usr/bin/env")
            .args(args.iter().copied())
            .current_dir(workspace_path)
            .output()
            .map_err(|e| format!("dependency audit spawn failed: {e}"))?;
        let text = String::from_utf8_lossy(&output.stdout).to_string()
            + String::from_utf8_lossy(&output.stderr).as_ref();
        return Ok(parse_dependency_audit_json(
            &text,
            label,
            output.status.code().unwrap_or(-1),
        ));
    }
    Ok(pack_payload(
        "audit_security_dependencies",
        vec![],
        false,
        "No supported dependency manifest found for security dependency audit.".to_string(),
        json!({"signal_type":"pattern","promotion_gate":"strict_verified"}),
        vec![],
        vec![],
    ))
}

fn parse_dependency_audit_json(output: &str, manager: &str, status: i32) -> Value {
    let lower = output.to_lowercase();
    let critical = lower.contains("\"critical\":") && !lower.contains("\"critical\":0");
    let high = lower.contains("\"high\":") && !lower.contains("\"high\":0");
    if !critical && !high && status == 0 {
        return pack_payload(
            "audit_security_dependencies",
            vec![],
            true,
            format!("No blocking dependency vulnerabilities reported by {manager} audit."),
            json!({"signal_type":"pattern","promotion_gate":"strict_verified"}),
            vec![manager.to_string()],
            vec![],
        );
    }
    let severity = if critical { "critical" } else { "warning" };
    let blocking = critical;
    let confidence = if critical { 0.92 } else { 0.80 };
    let finding = make_finding(
        severity,
        "security",
        "securityAuditor",
        &format!("{manager}-dependency-audit"),
        None,
        &format!("{manager} audit reported vulnerable dependencies."),
        "Review the dependency audit report, update or replace vulnerable packages, and re-run the audit.",
        Some(confidence),
        Some(&output.chars().take(400).collect::<String>()),
        blocking,
        Some("audit_security_dependencies".to_string()),
    );
    pack_payload(
        "audit_security_dependencies",
        vec![finding],
        true,
        format!("Dependency audit reported vulnerabilities for {manager}."),
        json!({"signal_type":"pattern","verification_hint":"Conferma advisory, reachability e lockfile effettivo prima della promozione","promotion_gate":"strict_verified","behavioral_impact":"runtime_dependency_risk"}),
        vec![manager.to_string()],
        vec![],
    )
}

pub(crate) fn run_security_supply_chain(
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    let deps = run_security_dependencies(workspace_path)?;
    let mut findings: Vec<Value> = deps
        .get("findings")
        .and_then(|f| f.as_array())
        .cloned()
        .unwrap_or_default();
    let mut adapters: Vec<String> = deps
        .get("adaptersUsed")
        .and_then(|a| a.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let cov0 = deps
        .get("coverageAvailable")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    if let Ok(out) = Command::new("osv-scanner")
        .args(["--recursive", "."])
        .current_dir(workspace_path)
        .output()
    {
        adapters.push("osv-scanner".to_string());
        let txt = String::from_utf8_lossy(&out.stdout).to_string()
            + String::from_utf8_lossy(&out.stderr).as_ref();
        let lower = txt.to_lowercase();
        if lower.contains("vulnerabilities")
            || lower.contains("severity")
            || (lower.contains("id:") && lower.contains("ghsa"))
        {
            findings.push(make_finding(
                "warning",
                "security",
                "securityAuditor",
                "osv-scanner",
                None,
                "osv-scanner ha rilevato advisory potenzialmente rilevanti nella supply chain.",
                "Conferma reachability e aggiorna dipendenze colpite.",
                Some(0.74),
                Some(&txt.chars().take(400).collect::<String>()),
                false,
                Some("audit_security_supply_chain".to_string()),
            ));
        }
    }

    let coverage = cov0 || !adapters.is_empty() || !scope_files.is_empty();
    dedupe_findings_ids(&mut findings);
    let summary = if findings.is_empty() {
        "Nessuna anomalia supply-chain rilevata.".to_string()
    } else {
        format!(
            "Rilevate {} anomalie supply-chain/dependency.",
            findings.len()
        )
    };
    Ok(pack_payload(
        "audit_security_supply_chain",
        findings,
        coverage,
        summary,
        json!({"signal_type":"pattern","verification_hint":"Conferma advisory, reachability e lockfile effettivo prima della promozione","promotion_gate":"strict_verified","behavioral_impact":"runtime_dependency_risk"}),
        adapters,
        vec![],
    ))
}

fn dedupe_findings_ids(findings: &mut Vec<Value>) {
    let mut seen = HashSet::new();
    findings.retain(|f| {
        let id = f
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        seen.insert(id)
    });
}
