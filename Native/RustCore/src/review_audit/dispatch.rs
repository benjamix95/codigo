use super::bugs;
use super::helpers::run_pattern_tool;
use super::perf_correlate;
use super::perf_trending;
use super::performance;
use super::security;
use serde_json::{json, Value};

pub(crate) fn dispatch_standard_audit(
    tool_name: &str,
    scope_files: Vec<String>,
    workspace_path: &str,
) -> Result<Value, String> {
    match tool_name {
        "audit_security_dataflow" => security::run_security_dataflow(scope_files, workspace_path),
        "audit_security_authz" => security::run_security_authz(scope_files, workspace_path),
        "audit_security_crypto" => run_pattern_tool(
            "audit_security_crypto",
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
            "audit_security_deserialization",
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
            "audit_security_surface",
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
        "audit_security_secrets" => security::run_security_secrets(scope_files, workspace_path),
        "audit_security_patterns" => security::run_security_patterns(scope_files, workspace_path),
        "audit_security_dependencies" => security::run_security_dependencies(workspace_path),
        "audit_security_supply_chain" => security::run_security_supply_chain(scope_files, workspace_path),
        "audit_bug_nil_crash_paths" => bugs::run_bug_nil_crash_paths(scope_files, workspace_path),
        "audit_bug_test_impact" => bugs::run_bug_test_impact(scope_files, workspace_path),
        "audit_bug_test_gaps" => bugs::run_bug_test_gaps(scope_files, workspace_path),
        "audit_bug_state_machine" => bugs::run_bug_state_machine(scope_files, workspace_path),
        "audit_bug_concurrency" => run_pattern_tool(
            "audit_bug_concurrency",
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
            "audit_bug_error_handling",
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
        "audit_bug_api_contracts" => bugs::run_bug_api_contracts(scope_files, workspace_path),
        "audit_bug_diff_risks" => bugs::run_bug_diff_risks(scope_files, workspace_path),
        "audit_bug_hotspots" => bugs::run_bug_hotspots(scope_files, workspace_path),
        "audit_bug_dependency_drift" => bugs::run_bug_dependency_drift(scope_files, workspace_path),
        "audit_bug_diff_semantics" => bugs::run_bug_diff_semantics(scope_files, workspace_path),
        // Performance tools
        "audit_perf_bottlenecks" => performance::run_perf_bottlenecks(scope_files, workspace_path),
        "audit_perf_memory" => performance::run_perf_memory(scope_files, workspace_path),
        "audit_perf_ui_responsiveness" => {
            performance::run_perf_ui_responsiveness(scope_files, workspace_path)
        }
        "audit_perf_startup" => performance::run_perf_startup(scope_files, workspace_path),
        "audit_perf_hot_paths" => performance::run_perf_hot_paths(scope_files, workspace_path),
        "audit_perf_correlate" => {
            perf_correlate::run_perf_correlate(scope_files, workspace_path)
        }
        "audit_perf_trending" => {
            // Gather all perf results first, then compute trending
            let mut results = Vec::new();
            for t in performance_deep_tools() {
                if let Ok(r) = dispatch_standard_audit(t, scope_files.clone(), workspace_path) {
                    results.push(r);
                }
            }
            perf_trending::run_perf_trending(&results, workspace_path, true)
        }
        _ => Err("unsupported_tool".to_string()),
    }
}

pub(crate) fn security_deep_tools() -> &'static [&'static str] {
    &[
        "audit_security_secrets",
        "audit_security_dependencies",
        "audit_security_patterns",
        "audit_security_dataflow",
        "audit_security_authz",
        "audit_security_crypto",
        "audit_security_deserialization",
        "audit_security_surface",
        "audit_security_supply_chain",
    ]
}

pub(crate) fn bug_hunt_deep_tools() -> &'static [&'static str] {
    &[
        "audit_bug_diff_risks",
        "audit_bug_test_gaps",
        "audit_bug_hotspots",
        "audit_bug_nil_crash_paths",
        "audit_bug_state_machine",
        "audit_bug_concurrency",
        "audit_bug_error_handling",
        "audit_bug_api_contracts",
        "audit_bug_test_impact",
        "audit_bug_dependency_drift",
        "audit_bug_diff_semantics",
    ]
}

pub(crate) fn performance_deep_tools() -> &'static [&'static str] {
    &[
        "audit_perf_bottlenecks",
        "audit_perf_memory",
        "audit_perf_ui_responsiveness",
        "audit_perf_startup",
        "audit_perf_hot_paths",
    ]
}

pub(crate) fn performance_extended_tools() -> &'static [&'static str] {
    &[
        "audit_perf_bottlenecks",
        "audit_perf_memory",
        "audit_perf_ui_responsiveness",
        "audit_perf_startup",
        "audit_perf_hot_paths",
        "audit_perf_correlate",
        "audit_perf_trending",
    ]
}
