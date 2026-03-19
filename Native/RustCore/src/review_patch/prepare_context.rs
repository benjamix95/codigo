use super::models::{ReviewPatchPrepareContextRequest, ReviewPatchPrepareContextResponse};

pub fn build_prepare_context(
    request: ReviewPatchPrepareContextRequest,
) -> ReviewPatchPrepareContextResponse {
    let verification = trim_or_default(request.verification_report.as_deref());
    if verification == "n/a" {
        return ReviewPatchPrepareContextResponse::error(
            "finding is not verified and cannot produce a patch preview",
        );
    }

    let branch_name = format!(
        "codex/review-patch-{}",
        request.finding_id.chars().take(8).collect::<String>().to_lowercase()
    );
    let prompt = format!(
        "Sei in una worktree temporanea creata solo per preparare una patch preview.\n\
Devi modificare i file target e fermarti senza fare commit.\n\n\
Sessione review: {}\n\
Finding: {}\n\
File: {}\n\
Riga: {}\n\
Messaggio: {}\n\
Verifica: {}\n\
Fix suggerito: {}\n\
Invariante atteso: {}\n\
Repro o reasoning: {}\n\n\
Regole:\n\
- modifica solo i file strettamente necessari a risolvere questo finding;\n\
- mantieni il patch set minimo e leggibile;\n\
- non fare commit, push o merge;\n\
- non introdurre refactor estranei;\n\
- al termine lascia le modifiche nel worktree e fermati.",
        request.session_id,
        request.finding_id,
        request.file_path,
        request
            .line_number
            .map(|value| value.to_string())
            .unwrap_or_else(|| "n/a".to_string()),
        request.message,
        verification,
        trim_or_default(request.suggested_fix.as_deref()),
        trim_or_default(request.expected_invariant.as_deref()),
        trim_or_default(request.repro_or_reasoning.as_deref()),
    );

    ReviewPatchPrepareContextResponse::success(branch_name, prompt)
}

fn trim_or_default(value: Option<&str>) -> String {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("n/a")
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_prepare_context_emits_branch_name_and_prompt() {
        let response = build_prepare_context(ReviewPatchPrepareContextRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            finding_id: "FindingABC123".to_string(),
            file_path: "Sources/File.swift".to_string(),
            line_number: Some(42),
            message: "Invariant broken".to_string(),
            verification_report: Some("Verified".to_string()),
            suggested_fix: Some("Restore guard".to_string()),
            expected_invariant: Some("Terminal event only once".to_string()),
            repro_or_reasoning: Some("Retry duplicates completion".to_string()),
        });

        assert!(!response.is_error);
        assert_eq!(
            response.branch_name.as_deref(),
            Some("codex/review-patch-findinga")
        );
        let prompt = response.prompt.as_deref().unwrap_or_default();
        assert!(prompt.contains("Sessione review: session-1"));
        assert!(prompt.contains("Fix suggerito: Restore guard"));
    }

    #[test]
    fn build_prepare_context_rejects_unverified_finding() {
        let response = build_prepare_context(ReviewPatchPrepareContextRequest {
            schema_version: 1,
            session_id: "session-1".to_string(),
            finding_id: "finding-1".to_string(),
            file_path: "Sources/File.swift".to_string(),
            line_number: None,
            message: "Invariant broken".to_string(),
            verification_report: None,
            suggested_fix: None,
            expected_invariant: None,
            repro_or_reasoning: None,
        });

        assert!(response.is_error);
    }
}
