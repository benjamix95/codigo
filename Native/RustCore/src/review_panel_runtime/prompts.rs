use super::models::{ReviewPanelPromptRequest, ReviewPanelPromptResponse};
use std::collections::BTreeSet;

pub fn build_prompt(request: ReviewPanelPromptRequest) -> ReviewPanelPromptResponse {
    match request.prompt_kind.as_str() {
        "combined" => ReviewPanelPromptResponse::success(combined_prompt(&request)),
        "standard" => ReviewPanelPromptResponse::success(standard_prompt(&request)),
        "security_audit" => ReviewPanelPromptResponse::success(security_audit_prompt(&request)),
        "bug_finder" => ReviewPanelPromptResponse::success(bug_finder_prompt(&request)),
        "branch_review" => ReviewPanelPromptResponse::success(branch_review_prompt(&request)),
        "commit_range" => ReviewPanelPromptResponse::success(commit_range_prompt(&request)),
        "chat_context" => ReviewPanelPromptResponse::success(chat_context_prompt(&request)),
        kind => ReviewPanelPromptResponse::error(
            "unsupported_prompt_kind",
            &format!("Unsupported prompt kind: {kind}"),
        ),
    }
}

fn combined_prompt(request: &ReviewPanelPromptRequest) -> String {
    let mut sections = vec![scope_header(request)];
    let selected = normalized_modes(&request.selected_modes);
    if selected.is_empty() || selected.contains("standard") {
        sections.push(STANDARD_FOCUS.to_string());
    }
    if selected.contains("securityAudit") {
        sections.push(SECURITY_FOCUS.to_string());
    }
    if selected.contains("bugFinder") {
        sections.push(BUG_FOCUS.to_string());
    }
    if let Some(extra) = non_empty(&request.custom_instructions) {
        sections.push(format!("Additional instructions:\n{extra}"));
    }
    sections.join("\n\n")
}

fn standard_prompt(request: &ReviewPanelPromptRequest) -> String {
    let base = format!(
        "{}\nRun a comprehensive code review covering:\n- P0 (Critical): Security vulnerabilities, data loss risks, crash bugs\n- P1 (High): Logic errors, performance regressions, API misuse\n- P2 (Medium): Code quality, maintainability, potential bugs\n- P3 (Low): Style, documentation, minor improvements\n\nFor each finding, provide: severity, file, line range, description, and a suggested fix.",
        default_scope_tag(request)
    );
    match non_empty(&request.custom_instructions) {
        Some(extra) => format!("{base}\n\nAdditional instructions:\n{extra}"),
        None => base,
    }
}

fn security_audit_prompt(request: &ReviewPanelPromptRequest) -> String {
    format!(
        "{} [MODE:security-audit]\nRun a thorough security-focused code review. Priority areas:\n\n1. **Injection vulnerabilities**: SQL injection, XSS, command injection, path traversal\n2. **Authentication/Authorization**: Bypasses, missing checks, privilege escalation\n3. **Secrets & credentials**: Hardcoded keys, tokens, passwords in source code\n4. **Unsafe deserialization**: Unvalidated input, unsafe casting, type confusion\n5. **File & network handling**: Unsafe file operations, SSRF, unvalidated URLs\n6. **Dependency risks**: Known CVEs in package manifests, outdated libraries\n7. **Cryptographic issues**: Weak algorithms, improper random generation, key management\n8. **Data exposure**: Logging sensitive data, excessive error details, PII leaks\n\nReport each finding with:\n- Severity (Critical/High/Medium/Low)\n- Affected file and line range\n- Attack vector description\n- CVSS-like impact assessment\n- Recommended mitigation with code example",
        default_scope_tag(request)
    )
}

fn bug_finder_prompt(request: &ReviewPanelPromptRequest) -> String {
    format!(
        "{} [MODE:bug-finder]\nRun a bug-focused code review. Look specifically for:\n\n1. **Null/nil dereference**: Force unwraps, unguarded optionals, missing nil checks\n2. **Race conditions**: Shared mutable state, actor isolation violations, data races\n3. **Logic errors**: Off-by-one, incorrect comparisons, wrong operator precedence\n4. **Memory issues**: Retain cycles, leaked resources, unbounded growth\n5. **Error handling**: Swallowed errors, incorrect catch blocks, missing error propagation\n6. **API misuse**: Wrong parameter types/order, deprecated APIs, contract violations\n7. **Edge cases**: Empty collections, boundary values, integer overflow\n8. **State management**: Invalid state transitions, stale data, inconsistent updates\n\nFor each bug found, provide:\n- Severity and category\n- Exact reproduction scenario\n- Root cause analysis\n- Fix with code diff",
        default_scope_tag(request)
    )
}

fn branch_review_prompt(request: &ReviewPanelPromptRequest) -> String {
    let branch = non_empty(&request.branch_name).unwrap_or_else(|| "unknown".to_string());
    let current = non_empty(&request.current_branch).unwrap_or_else(|| "main".to_string());
    format!(
        "[AGAINST:{current}..{branch}]\nReview all changes on branch '{branch}' since it diverged from '{current}'.\n\nAnalyze the entire branch for:\n- Cumulative impact of all commits\n- Patterns of issues across multiple files\n- Architectural concerns from the combined changeset\n- Regression risks when merging\n- Incomplete features or TODO items left behind\n- Test coverage gaps for new code\n\nGroup findings by commit when possible, and highlight cross-cutting concerns."
    )
}

fn commit_range_prompt(request: &ReviewPanelPromptRequest) -> String {
    let shas = request.commits.join(", ");
    let scope = if request.commits.len() == 1 {
        format!("[AGAINST:{}^..{}]", request.commits[0], request.commits[0])
    } else if let (Some(first), Some(last)) = (request.commits.last(), request.commits.first()) {
        format!("[AGAINST:{first}^..{last}]")
    } else {
        "[REVIEW_SCOPE:uncommitted]".to_string()
    };
    format!(
        "{scope}\nReview the following commits: {shas}\n\nFor each commit, analyze:\n- Code quality and correctness\n- Security implications\n- Performance impact\n- Test coverage\n\nSummarize findings grouped by commit SHA with cross-references."
    )
}

fn chat_context_prompt(request: &ReviewPanelPromptRequest) -> String {
    let session_line = request
        .active_session_id
        .as_ref()
        .map(|id| format!("- Active review session: {id}"))
        .unwrap_or_else(|| "- Active review session: unavailable".to_string());
    let conversation_line = request
        .conversation_id
        .as_ref()
        .map(|id| format!("- Conversation scope: {id}"))
        .unwrap_or_else(|| "- Conversation scope: none".to_string());
    let session_summary = request.session_summary.as_deref().unwrap_or("");
    let findings = request.findings_count.unwrap_or(0);
    let open = request.open_count.unwrap_or(0);
    let user = request.user_message.as_deref().unwrap_or("");
    format!(
        "You are the dedicated chat for an active code review session.\nYour primary focus is bug hunting, regression detection, security review, and test gaps.\nYou have access to the full tool-enabled review environment exposed by the runtime. When a tool can materially improve accuracy, use it instead of guessing.\nPrefer bug-hunter and security-auditor behaviour: verify before asserting, prioritize concrete risks, and surface only actionable findings.\n\nCurrent review state:\n{session_line}\n{conversation_line}\n{session_summary}\n- Total findings: {findings}\n- Open findings: {open}\n\nResponse contract:\n- Use well-structured markdown, not dense plain text.\n- Start with a short title or verdict only when useful.\n- Prefer these sections when applicable: `## Findings`, `## Security`, `## Reproduction`, `## Fix`, `## Risks`, `## Next checks`.\n- Use bullets for distinct issues and short paragraphs for explanations.\n- Reference findings by severity, file, and line whenever possible.\n- When no bug or security issue is confirmed, say that explicitly and note residual risks or missing verification.\n- Do not pad the answer with generic praise or filler.\n\nIf you identify NEW actionable findings that should appear in the Findings tab, append at the very end a fenced block exactly like this:\n\n```review_findings\n{{\n  \"findings\": [\n    {{\n      \"severity\": \"warning\",\n      \"category\": \"correctness\",\n      \"file\": \"Sources/App/Main.swift\",\n      \"line\": 42,\n      \"message\": \"Short actionable finding\",\n      \"suggested_fix\": \"Concrete fix guidance\",\n      \"confidence\": 0.82\n    }}\n  ]\n}}\n```\n\nRules:\n- Reuse the current active review session for review tools and findings updates.\n- Do not call `review_start` unless the user explicitly asks to start a new review session.\n- When a review tool accepts them, always pass `session_id` and `conversation_id` for the active session above.\n- Emit the block only when you are introducing or updating actionable findings.\n- If there are no actionable findings, do not emit the block.\n- Use categories: correctness, regression, concurrency, security, tests, maintainability, performance, other.\n- Severity: critical, warning, suggestion, info.\n- Keep the fenced `review_findings` block as the final trailing block only.\n- Do not wrap the whole answer in a code fence.\n\nUser: {user}"
    )
}

fn scope_header(request: &ReviewPanelPromptRequest) -> String {
    match request.scope_kind.as_deref().unwrap_or("uncommitted") {
        "branch" => branch_review_prompt(request),
        "commits" if !request.commits.is_empty() => commit_range_prompt(request),
        _ => format!(
            "{}\nRun a code review over the selected scope.",
            default_scope_tag(request)
        ),
    }
}

fn default_scope_tag(request: &ReviewPanelPromptRequest) -> String {
    request
        .scope_tag
        .as_ref()
        .filter(|value| !value.trim().is_empty())
        .cloned()
        .unwrap_or_else(|| "[REVIEW_SCOPE:uncommitted]".to_string())
}

fn non_empty(value: &Option<String>) -> Option<String> {
    value
        .as_ref()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

fn normalized_modes(modes: &[String]) -> BTreeSet<String> {
    modes
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect()
}

const STANDARD_FOCUS: &str = "Standard focus:\n- P0 (Critical): Security vulnerabilities, data loss risks, crash bugs\n- P1 (High): Logic errors, performance regressions, API misuse\n- P2 (Medium): Code quality, maintainability, potential bugs\n- P3 (Low): Style, documentation, minor improvements\n\nFor each finding, provide severity, file, line range, description, and a suggested fix.";
const SECURITY_FOCUS: &str = "Security focus:\n1. Injection vulnerabilities: SQL injection, XSS, command injection, path traversal\n2. Authentication and authorization: bypasses, missing checks, privilege escalation\n3. Secrets and credentials: hardcoded keys, tokens, passwords\n4. Unsafe deserialization and validation issues\n5. File and network handling: unsafe file ops, SSRF, unvalidated URLs\n6. Data exposure in logs and error surfaces";
const BUG_FOCUS: &str = "Bug focus:\n1. Nil or null dereference and force unwraps\n2. Race conditions and invalid state transitions\n3. Logic errors, off-by-one, wrong comparisons\n4. Memory issues and unbounded growth\n5. Error handling gaps and swallowed failures\n6. Edge cases and API misuse";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn combined_prompt_includes_selected_sections() {
        let response = build_prompt(ReviewPanelPromptRequest {
            schema_version: 1,
            prompt_kind: "combined".to_string(),
            scope_tag: Some("[REVIEW_SCOPE:uncommitted]".to_string()),
            scope_kind: Some("uncommitted".to_string()),
            current_branch: Some("main".to_string()),
            branch_name: None,
            commits: Vec::new(),
            selected_modes: vec![
                "standard".to_string(),
                "securityAudit".to_string(),
                "bugFinder".to_string(),
            ],
            custom_instructions: Some("Check API edges".to_string()),
            user_message: None,
            session_summary: None,
            findings_count: None,
            open_count: None,
            active_session_id: None,
            conversation_id: None,
        });

        let prompt = response.prompt.expect("prompt");
        assert!(prompt.contains("Standard focus:"));
        assert!(prompt.contains("Security focus:"));
        assert!(prompt.contains("Bug focus:"));
        assert!(prompt.contains("Check API edges"));
    }

    #[test]
    fn branch_prompt_uses_current_branch_context() {
        let prompt = branch_review_prompt(&ReviewPanelPromptRequest {
            schema_version: 1,
            prompt_kind: "branch_review".to_string(),
            scope_tag: None,
            scope_kind: Some("branch".to_string()),
            current_branch: Some("main".to_string()),
            branch_name: Some("feature/refactor".to_string()),
            commits: Vec::new(),
            selected_modes: Vec::new(),
            custom_instructions: None,
            user_message: None,
            session_summary: None,
            findings_count: None,
            open_count: None,
            active_session_id: None,
            conversation_id: None,
        });

        assert!(prompt.contains("[AGAINST:main..feature/refactor]"));
    }

    #[test]
    fn chat_context_prompt_keeps_review_tool_rules() {
        let prompt = chat_context_prompt(&ReviewPanelPromptRequest {
            schema_version: 1,
            prompt_kind: "chat_context".to_string(),
            scope_tag: None,
            scope_kind: None,
            current_branch: None,
            branch_name: None,
            commits: Vec::new(),
            selected_modes: Vec::new(),
            custom_instructions: None,
            user_message: Some("controlla".to_string()),
            session_summary: Some("Phase: running".to_string()),
            findings_count: Some(3),
            open_count: Some(2),
            active_session_id: Some("review-1".to_string()),
            conversation_id: Some("conv-1".to_string()),
        });

        assert!(prompt.contains("primary focus is bug hunting"));
        assert!(prompt.contains("Do not call `review_start` unless the user explicitly asks"));
        assert!(prompt.contains("always pass `session_id` and `conversation_id`"));
    }
}
