import Foundation

/// Testo model-facing allineato a [`tool_descriptions.json`](../../../../Native/CoderideMCPServerRust/src/tool_descriptions.json).
/// Aggiornare il blob quando si modifica il JSON Rust (stesso contenuto).
enum RustSyncedToolDescriptions {
    /// `mcpName` coincide con `Tool.name` (es. `coderide_read`).
    static func text(mcpName: String, fallback: String) -> String {
        parsed[mcpName] ?? fallback
    }

    private static let parsed: [String: String] = {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(embedded.utf8)) as? [String: String] else {
            assertionFailure("tool_descriptions embedded JSON non valido")
            return [:]
        }
        return obj
    }()

    private static let embedded = """
    {
      "coderide_activate_plan_mode": "Open or focus the IDE plan panel for structured multi-step planning before large edits. Usage: optional reason string explaining why plan mode is needed.",
      "coderide_bughunter_autofix_apply": "Apply autofix for top verified finding. Usage: run_id (required); optional conversation_id.",
      "coderide_bughunter_autofix_commit": "Apply+commit autofix and queue follow-up review. Usage: run_id (required); optional conversation_id.",
      "coderide_bughunter_autofix_preview": "Preview autofix for top verified BugHunter finding. Usage: run_id (required); optional conversation_id.",
      "coderide_bughunter_cancel_run": "Stop an in-flight BugHunter run. Usage: run_id (required); optional conversation_id.",
      "coderide_bughunter_commit_window": "Run BugHunter on a commit plus correlated history. Usage: git_root, primary_commit (required); optional conversation_id.",
      "coderide_bughunter_explain_cluster": "Explain strongest correlated defect cluster. Usage: run_id (required); optional conversation_id.",
      "coderide_bughunter_findings": "List BugHunter-linked findings through review. Usage: run_id; optional kind/severity/status/conversation_id.",
      "coderide_bughunter_install_hook": "Install managed post-commit BugHunter hook. Usage: git_root (required).",
      "coderide_bughunter_run_history": "List prior BugHunter runs with summaries. Usage: optional conversation_id.",
      "coderide_bughunter_start": "Start BugHunter over uncommitted commits/commit windows/branch windows. Usage: source_kind, git_root plus primary_commit/branch fields as required by kind; optional conversation_id.",
      "coderide_bughunter_status": "Poll BugHunter run + linked review status. Usage: run_id; optional conversation_id.",
      "coderide_bughunter_uninstall_hook": "Remove managed BugHunter hook. Usage: git_root (required).",
      "coderide_codebase_search": "Index-backed symbol search by name/pattern/kind (faster than grep for definitions). Usage: query; optional kind, filePattern/path.",
      "coderide_create_file": "Atomically create a new file; fails if the path already exists. Usage: path and full content.",
      "coderide_diagnostics": "Run a full diagnostic/build pass and return structured errors/warnings. Usage: optional manager string if the host supports it; slower than read_lints.",
      "coderide_export_debug_bundle": "Zip SoloCode AgentDebug NDJSON traces into a shareable .solocode bundle. Usage: optional workspace_roots CSV for multi-root fingerprint alignment.",
      "coderide_file_outline": "Structural outline (symbols/sections) for one file. Usage: path.",
      "coderide_find_files": "Fuzzy / index-backed file discovery by name. Usage: query or pattern; optional path, filePattern, extension.",
      "coderide_find_references": "List usages before refactors. Usage: query or name for the symbol.",
      "coderide_find_symbol": "Locate symbol definitions (types, functions, methods). Usage: query or name; optional kind filter.",
      "coderide_git_diff": "Show working-tree or scoped diff. Usage: optional path; optional staged hint when supported.",
      "coderide_glob": "Find paths matching a glob (e.g. **/*.swift). Usage: pattern; optional path root.",
      "coderide_grep": "Ripgrep-style content search (regex, filters, context lines). Usage: query or pattern; optional path/pathScope, fileType, glob, context_lines, case_sensitive, multiline, output_mode.",
      "coderide_list_dir": "List files and subdirectories under a path (directory discovery). Usage: path to the folder to enumerate.",
      "coderide_mermaid_render": "Render Mermaid in the IDE (architecture/flow visualization). Usage: code (required); optional title.",
      "coderide_plan_create": "Create/replace the visible IDE plan snapshot. Usage: goal (required); optional steps JSON, chosen_path, conversation_id, replace_existing.",
      "coderide_plan_diff": "Compare two plan snapshots (what changed between rounds). Usage: from_snapshot_id (required); optional to_snapshot_id, conversation_id.",
      "coderide_plan_history_read": "Read historical plan snapshots. Usage: optional conversation_id, limit.",
      "coderide_plan_read": "Fetch latest plan snapshot. Usage: optional conversation_id, include_history, history_limit.",
      "coderide_plan_request_user_input": "Block plan flow on structured clarification questions in the IDE. Usage: questions JSON (required); optional title, phase, round, context, conversation_id.",
      "coderide_plan_set_walkthrough": "Store final walkthrough markdown and outcome for the plan. Usage: markdown (required); optional summary, outcome, conversation_id.",
      "coderide_plan_step_batch_update": "Apply many step updates in one call. Usage: updates JSON array; optional conversation_id.",
      "coderide_plan_step_dependency_set": "Set prerequisites for a step. Usage: step_id, depends_on JSON array; optional conversation_id.",
      "coderide_plan_step_reorder": "Reorder steps. Usage: ordered_step_ids JSON array; optional conversation_id.",
      "coderide_plan_step_update": "Lightweight step status/title update while executing the plan in the IDE. Usage: step_id and status (required); optional title.",
      "coderide_plan_step_upsert": "Create/update one plan step with metadata. Usage: step_id and status (required); optional title, description, target_file, linked_files, depends_on, notes, conversation_id.",
      "coderide_policy_ack": "Acknowledge a repository policy hash before mutating tools when the host requires it. Usage: hash (required).",
      "coderide_read": "Read a file from the workspace with line numbers. Always read before editing. Usage: path (required). Optional offset/limit as line hints when supported by the host.",
      "coderide_read_lints": "Read current linter/IDE diagnostics without a full build when available. Usage: optional path filter, severity, limit.",
      "coderide_read_range": "Read an inclusive line slice from a file (faster than whole file for large sources). Usage: path; start and end as start_line/end_line or start/end integers when available.",
      "coderide_regex_replace": "Regex-powered single-file replace (supports capture groups in replacement). Usage: path, pattern, replacement; optional flags string.",
      "coderide_review_apply_fix": "Apply an IDE-suggested fix for a finding. Usage: finding identifiers per host schema (finding_id, session_id, etc.).",
      "coderide_review_apply_patch": "Apply the verified patch to the workspace. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_close_finding": "Close a finding after fix or explicit resolution. Usage: finding_id, session_id; optional reason; optional conversation_id.",
      "coderide_review_comment": "Attach analyst comment or metadata to a finding/session. Usage: fields per host schema.",
      "coderide_review_configure": "Adjust live review settings (workers, rounds, toggles). Usage: fields per host schema.",
      "coderide_review_diff_summary": "Summarize diffs associated with the review scope (read-only). Usage: session identifiers as required.",
      "coderide_review_dismiss": "Dismiss a finding with rationale. Usage: finding_id/session_id plus dismiss fields per host.",
      "coderide_review_findings": "Filter/list findings (severity, file, status, origin). Usage: optional filters; session_id/conversation_id if needed.",
      "coderide_review_get_outcome": "Fetch structured outcome summary for a session. Usage: session_id (required); optional conversation_id.",
      "coderide_review_list_sessions": "Enumerate review sessions (including finished). Usage: optional conversation_id.",
      "coderide_review_merge_pr": "Merge the PR for a finding when policy allows. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_open_pr": "Open a PR for the finding’s patch branch. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_prepare_patch": "Materialize a patch plan for a verified finding. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_preview_patch": "Read-only view of the generated patch artifact. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_resolve_conflicts": "Attempt safe conflict resolution on the review branch. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_revalidate_finding": "Re-run validation after patch application. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_rollback_patch": "Undo an applied patch when rollback metadata exists. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_start": "Start a code review session over uncommitted/staged/or-against-ref scope. Usage: scope/ref and backends as needed; optional session_id/conversation_id.",
      "coderide_review_status": "Poll phase/workers/round status for the active review. Usage: optional session_id/conversation_id when multiple sessions exist.",
      "coderide_review_verify_finding": "Verify/promote a candidate finding before patching. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_review_verify_patch": "Validate patch application (dry-run or checks). Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_run_tests": "Run tests (cargo/swift test/xcodebuild when applicable). Usage: optional filter; optional scheme for Xcode.",
      "coderide_security_apply_patch": "Apply verified security patch. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_close_finding": "Close or reject a security finding with reason. Usage: finding_id, session_id; optional reason; optional conversation_id.",
      "coderide_security_findings": "List security findings (verified/candidate). Usage: session_id; optional filters kind/severity/status/conversation_id.",
      "coderide_security_prepare_patch": "Prepare patch for verified security finding. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_preview_patch": "Preview stored security patch (read-only). Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_revalidate_finding": "Post-fix security revalidation. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_rollback_patch": "Rollback applied security patch. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_start": "Start a security-hardened review session (shared VerifiedFindings backend). Usage: scope/ref; optional session_id/conversation_id.",
      "coderide_security_status": "Read security gate/session status. Usage: session_id when needed; optional conversation_id.",
      "coderide_security_verify_finding": "Promote/verify a security finding before patching. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_security_verify_patch": "Validate security patch. Usage: finding_id and session_id (required); optional conversation_id.",
      "coderide_semantic_search": "Meaning-first code search (natural language) with optional directory scoping. Usage: query; optional target_directories/pathScope/path, num_results/limit.",
      "coderide_show_swarm_panel": "Reveal swarm/multi-agent UI. Usage: optional swarm_id.",
      "coderide_show_task_panel": "Reveal IDE task/activity UI. Usage: typically empty args.",
      "coderide_skill": "Execute a local SKILL.md workflow from user skill dirs. Usage: skill or name; task or args describing the work—prefer this when a skill matches the request.",
      "coderide_str_replace": "Surgical edit: replace exactly one occurrence of old_string with new_string. Usage: path, old_string, new_string. old_string must match exactly; add context if it is not unique.",
      "coderide_subagent_bugHunter": "Spawn regression/crash-hunting specialist subagent. Usage: task (required).",
      "coderide_subagent_coder": "Spawn an editing subagent for isolated implementation work. Usage: task (required).",
      "coderide_subagent_docWriter": "Spawn documentation-focused subagent. Usage: task (required).",
      "coderide_subagent_explorer": "Spawn a read-only explorer subagent for parallel investigation. Usage: task (required) describing what to map/read.",
      "coderide_subagent_reviewer": "Spawn a reviewer subagent (quality/safety read-only review). Usage: task (required).",
      "coderide_subagent_securityAuditor": "Spawn security audit subagent. Usage: task (required).",
      "coderide_subagent_testWriter": "Spawn a tests-and-verification subagent. Usage: task (required).",
      "coderide_todo_read": "Read the shared IDE todo list / LiveCard items. Usage: no required fields.",
      "coderide_todo_write": "Update structured todos shown in the IDE. Usage: pass todos JSON batch and/or single-item fields title, status, priority, notes, activeForm, linkedFiles.",
      "coderide_web_fetch": "Fetch public URL and return Markdown content. Usage: url (required).",
      "coderide_web_search": "Internet search for up-to-date docs, APIs, CVEs, releases. Usage: query (required); optional explanation/maxResults.",
      "coderide_write": "Overwrite or create a file with full contents. Usage: path and content. Prefer coderide_str_replace for small edits to existing files."
    }
    """
}
