use crate::review_models::ReviewVerificationResultPayload;
use crate::review_value::get_str;
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;

pub fn verify_candidates(
    candidates: Vec<Value>,
    workspace_path: &str,
    scope_files: Vec<String>,
) -> Result<Vec<ReviewVerificationResultPayload>, String> {
    let normalized_scope: HashSet<String> = scope_files
        .into_iter()
        .map(|file| normalize_path(&file))
        .collect();
    let mut results = Vec::with_capacity(candidates.len());
    for candidate in candidates {
        results.push(verify_candidate(
            candidate,
            workspace_path,
            &normalized_scope,
        )?);
    }
    Ok(results)
}

fn verify_candidate(
    candidate: Value,
    workspace_path: &str,
    scope_files: &HashSet<String>,
) -> Result<ReviewVerificationResultPayload, String> {
    let candidate_id = get_str(&candidate, "id").unwrap_or_default().to_string();
    let file_path = normalize_path(get_str(&candidate, "filePath").unwrap_or_default());
    if !scope_files.is_empty() && !scope_files.contains(&file_path) {
        return Ok(result(
            candidate_id,
            "rejected_false_positive",
            "scope_guard",
            "Il file del candidate è fuori dallo scope corrente della review.",
            Some("outside_review_scope"),
        ));
    }

    let absolute_path = PathBuf::from(workspace_path).join(&file_path);
    let content = fs::read_to_string(&absolute_path)
        .map_err(|err| format!("failed to read {}: {err}", absolute_path.display()))?;
    let lines: Vec<&str> = content.lines().collect();
    let line_number = candidate.get("lineNumber").and_then(Value::as_i64);
    let evidence = trimmed_evidence(&candidate);

    if let Some(line_number) = line_number {
        if line_number > 0 && (line_number as usize) <= lines.len() {
            let line_text = lines[(line_number as usize) - 1];
            if let Some(evidence) = &evidence {
                if line_text.to_lowercase().contains(&evidence.to_lowercase()) {
                    return Ok(result(
                        candidate_id,
                        "verified",
                        "line_evidence_match",
                        &format!(
                            "L'evidenza del candidate coincide con il contesto della riga {}.",
                            line_number
                        ),
                        None,
                    ));
                }
            }
            if matches_known_risk(
                get_str(&candidate, "message").unwrap_or_default(),
                line_text,
            ) {
                return Ok(result(
                    candidate_id,
                    "inconclusive",
                    "semantic_risk_match",
                    &format!("La riga {} contiene un pattern coerente con il rischio segnalato, ma la corrispondenza euristica non è sufficiente per promuoverlo automaticamente.", line_number),
                    None,
                ));
            }
            return Ok(result(
                candidate_id,
                "inconclusive",
                "context_mismatch",
                "Il candidate non è stato smentito, ma l'automazione non ha trovato prova sufficiente per promuoverlo a finding verificato.",
                None,
            ));
        }
    }

    if let Some(evidence) = evidence {
        if content.to_lowercase().contains(&evidence.to_lowercase()) {
            return Ok(result(
                candidate_id,
                "inconclusive",
                "file_evidence_search",
                &format!("L'evidenza del candidate compare nel file {}, ma senza un contesto di riga valido la verifica automatica non può promuoverlo a finding verificato.", file_path),
                None,
            ));
        }
    }
    Ok(result(
        candidate_id,
        "inconclusive",
        "missing_line_context",
        "Il candidate non ha un contesto di riga sufficiente per una verifica automatica affidabile.",
        None,
    ))
}

fn result(
    candidate_id: String,
    status: &str,
    method: &str,
    report: &str,
    false_positive_reason: Option<&str>,
) -> ReviewVerificationResultPayload {
    ReviewVerificationResultPayload {
        candidate_id,
        status: status.to_string(),
        method: method.to_string(),
        report: report.to_string(),
        false_positive_reason: false_positive_reason.map(ToString::to_string),
    }
}

fn trimmed_evidence(candidate: &Value) -> Option<String> {
    let evidence = get_str(candidate, "evidence")?.trim();
    if evidence.is_empty() {
        None
    } else {
        Some(evidence.to_string())
    }
}

fn normalize_path(path: &str) -> String {
    path.trim_start_matches("./").trim().to_string()
}

fn matches_known_risk(message: &str, line: &str) -> bool {
    let lower_message = message.to_lowercase();
    let lower_line = line.to_lowercase();
    [
        ("fatal", vec!["fatalerror("]),
        ("force-try", vec!["try!"]),
        ("forced cast", vec![" as! "]),
        ("deadlock", vec!["dispatchqueue.main.sync"]),
        ("html injection", vec!["innerhtml"]),
        (
            "secret",
            vec![
                "api_key",
                "access_token",
                "client_secret",
                "ghp_",
                "sk_live_",
            ],
        ),
        ("http", vec!["http://"]),
    ]
    .into_iter()
    .any(|(needle, tokens)| {
        lower_message.contains(needle) && tokens.into_iter().any(|token| lower_line.contains(token))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn verification_requires_line_context_for_promotion() {
        let root = std::env::temp_dir().join(format!(
            "review-verify-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("Service.swift"), "fatalError()\n").unwrap();
        let results = verify_candidates(
            vec![json!({
                "id": "candidate-1",
                "filePath": "Service.swift",
                "message": "Potential nil access",
                "evidence": "fatalError()"
            })],
            root.to_str().unwrap(),
            vec!["Service.swift".to_string()],
        )
        .unwrap();
        assert_eq!(results[0].status, "inconclusive");
    }
}
