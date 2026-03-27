import Foundation

extension ToolSchemaCatalog {
    static let workflowTools: [ToolSchemaEntry] =
        reviewWorkflowTools + securityWorkflowTools + bugHunterWorkflowTools

    private static let reviewWorkflowTools: [ToolSchemaEntry] = [
        workflowEntry(
            name: "review_start",
            descriptionFallback: "Start a code review session over uncommitted work, staged changes, or a diff against a ref.",
            properties: workflowStringProps([
                "scope": ("Review scope: uncommitted, staged, or against_ref.", ["uncommitted", "staged", "against_ref"]),
                "ref": ("Git ref when scope is against_ref (e.g. main, origin/develop).", nil),
                "max_workers": ("Max parallel fix workers (1–12), string-encoded.", nil),
                "max_rounds": ("Max review rounds (1–10), string-encoded.", nil),
                "analysis_only": ("If true, skip fix rounds (string true/false).", nil),
                "analysis_backend": ("Backend id for analysis phase.", nil),
                "execution_backend": ("Backend id for execution phase.", nil),
                "session_id": ("Optional unique session id; generated if omitted.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation UUID for concurrent sessions.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: []
        ),
        workflowEntry(name: "review_list_sessions", descriptionFallback: "List review sessions for the current conversation or globally.", properties: workflowStringProps([
            "conversation_id": ("Filter sessions tied to this conversation.", nil),
            "conversationId": ("Alias of conversation_id.", nil),
        ]), required: []),
        workflowEntry(name: "review_status", descriptionFallback: "Read the current code review session status.", properties: sessionScopeProps, required: []),
        workflowEntry(
            name: "review_findings",
            descriptionFallback: "List review findings with filters for severity, status, file, origin, and category.",
            properties: workflowStringProps([
                "session_id": ("Session to read findings from.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
                "severity": ("Filter by severity.", ["critical", "warning", "suggestion", "info"]),
                "kind": ("verified (default) or candidate findings.", ["verified", "candidate"]),
                "file": ("Substring match on file path.", nil),
                "status": ("Filter by finding status (open, dismissed, etc.).", nil),
                "origin": ("reviewer, bugHunter, securityAuditor, or audit_tool.", nil),
                "category": ("correctness, regression, concurrency, security, tests, maintainability, performance, other.", nil),
                "limit": ("Max rows (string integer).", nil),
            ]),
            required: []
        ),
        workflowPatchEntry(name: "review_apply_fix", descriptionFallback: "Apply an IDE-suggested fix for a review finding."),
        workflowPatchEntry(name: "review_verify_finding", descriptionFallback: "Verify/promote a candidate review finding before patching."),
        workflowPatchEntry(name: "review_prepare_patch", descriptionFallback: "Prepare a patch plan for a verified review finding."),
        workflowPatchEntry(name: "review_preview_patch", descriptionFallback: "Preview the generated patch for a verified review finding."),
        workflowPatchEntry(name: "review_apply_patch", descriptionFallback: "Apply a verified patch for a review finding."),
        workflowPatchEntry(name: "review_verify_patch", descriptionFallback: "Validate a review patch before applying it."),
        workflowPatchEntry(name: "review_revalidate_finding", descriptionFallback: "Re-run validation after applying a review patch."),
        workflowPatchEntry(name: "review_rollback_patch", descriptionFallback: "Rollback an applied review patch."),
        workflowPatchEntry(name: "review_open_pr", descriptionFallback: "Open a PR for the finding’s patch branch."),
        workflowPatchEntry(name: "review_merge_pr", descriptionFallback: "Merge the PR for a review finding when policy allows."),
        workflowPatchEntry(name: "review_resolve_conflicts", descriptionFallback: "Attempt safe conflict resolution on the review branch."),
        workflowEntry(
            name: "review_close_finding",
            descriptionFallback: "Close a review finding after fix or explicit resolution.",
            properties: workflowStringProps([
                "finding_id": ("Finding id to close.", nil),
                "session_id": ("Owning session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "reason": ("Why the finding is closed (human-readable).", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["finding_id", "session_id"]
        ),
        workflowEntry(
            name: "review_dismiss",
            descriptionFallback: "Dismiss a review finding with rationale.",
            properties: workflowStringProps([
                "finding_id": ("Finding id to dismiss.", nil),
                "reason": ("e.g. false_positive, wont_fix, by_design, duplicate.", nil),
                "session_id": ("Owning session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["finding_id", "session_id"]
        ),
        workflowEntry(
            name: "review_configure",
            descriptionFallback: "Configure a live review session.",
            properties: workflowStringProps([
                "max_workers": ("Parallel workers (string integer 1–12).", nil),
                "max_rounds": ("Rounds (string integer 1–10).", nil),
                "analysis_backend": ("Analysis backend id.", nil),
                "execution_backend": ("Execution backend id.", nil),
                "analysis_only": ("String true/false.", nil),
                "session_id": ("Session to reconfigure (required).", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["session_id"]
        ),
        workflowEntry(
            name: "review_diff_summary",
            descriptionFallback: "Summarize diffs associated with the review scope.",
            properties: workflowStringProps([
                "file": ("Optional single file; omit for whole scope.", nil),
                "origin": ("Optional finding origin filter.", nil),
                "category": ("Optional category filter.", nil),
                "session_id": ("Session id when multiple active.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: []
        ),
        workflowEntry(
            name: "review_comment",
            descriptionFallback: "Attach an analyst comment or metadata to a review finding.",
            properties: workflowStringProps([
                "finding_id": ("Finding to annotate.", nil),
                "content": ("Comment body.", nil),
                "author": ("Optional author label (default agent).", nil),
                "session_id": ("Owning session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["finding_id", "content", "session_id"]
        ),
        workflowEntry(name: "review_get_outcome", descriptionFallback: "Fetch the structured outcome summary for a review session.", properties: sessionScopeProps, required: ["session_id"]),
    ]

    private static let securityWorkflowTools: [ToolSchemaEntry] = [
        workflowEntry(
            name: "security_start",
            descriptionFallback: "Start a security-hardened review session.",
            properties: workflowStringProps([
                "scope": ("Security review scope.", ["uncommitted", "staged", "against_ref"]),
                "ref": ("Git ref when scope is against_ref.", nil),
                "session_id": ("Optional unique session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation UUID.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: []
        ),
        workflowEntry(name: "security_status", descriptionFallback: "Read the current security session status.", properties: sessionScopeProps, required: []),
        workflowEntry(
            name: "security_findings",
            descriptionFallback: "List security findings with filters.",
            properties: workflowStringProps([
                "session_id": ("Security session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
                "kind": ("verified or candidate.", ["verified", "candidate"]),
                "severity": ("Severity filter.", ["critical", "warning", "suggestion", "info"]),
                "status": ("Optional status filter.", nil),
            ]),
            required: []
        ),
        workflowPatchEntry(name: "security_verify_finding", descriptionFallback: "Promote or verify a security finding."),
        workflowPatchEntry(name: "security_prepare_patch", descriptionFallback: "Prepare a patch for a verified security finding."),
        workflowPatchEntry(name: "security_preview_patch", descriptionFallback: "Preview a stored security patch."),
        workflowPatchEntry(name: "security_apply_patch", descriptionFallback: "Apply a verified security patch."),
        workflowPatchEntry(name: "security_verify_patch", descriptionFallback: "Validate a security patch before apply."),
        workflowPatchEntry(name: "security_revalidate_finding", descriptionFallback: "Re-run security validation after a patch."),
        workflowPatchEntry(name: "security_rollback_patch", descriptionFallback: "Rollback an applied security patch."),
        workflowEntry(
            name: "security_close_finding",
            descriptionFallback: "Close or reject a security finding.",
            properties: workflowStringProps([
                "finding_id": ("Security finding id.", nil),
                "session_id": ("Owning session id.", nil),
                "sessionId": ("Alias of session_id.", nil),
                "reason": ("Closure reason.", nil),
                "conversation_id": ("Conversation scope.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["finding_id", "session_id"]
        ),
    ]

    private static let bugHunterWorkflowTools: [ToolSchemaEntry] = [
        workflowEntry(
            name: "bughunter_start",
            descriptionFallback: "Start BugHunter on uncommitted changes, a commit, or a commit window.",
            properties: workflowStringProps([
                "source_kind": ("What to scan.", ["uncommitted", "commit", "commit_window", "branch_window"]),
                "git_root": ("Repository root path.", nil),
                "primary_commit": ("Commit SHA for commit or commit_window runs.", nil),
                "branch_name": ("Branch for branch_window.", nil),
                "conversation_id": ("Optional conversation UUID.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: []
        ),
        workflowEntry(
            name: "bughunter_status",
            descriptionFallback: "Read BugHunter run status.",
            properties: workflowStringProps([
                "run_id": ("BugHunter run id returned by start.", nil),
                "conversation_id": ("Optional conversation UUID.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
                "kind": ("verified or candidate.", ["verified", "candidate"]),
                "severity": ("Filter severity.", ["critical", "warning", "suggestion", "info"]),
                "status": ("Optional status filter.", nil),
            ]),
            required: []
        ),
        workflowEntry(
            name: "bughunter_findings",
            descriptionFallback: "List BugHunter findings.",
            properties: workflowStringProps([
                "run_id": ("BugHunter run id returned by start.", nil),
                "conversation_id": ("Optional conversation UUID.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
                "kind": ("verified or candidate.", ["verified", "candidate"]),
                "severity": ("Filter severity.", ["critical", "warning", "suggestion", "info"]),
                "status": ("Optional status filter.", nil),
            ]),
            required: []
        ),
        workflowEntry(name: "bughunter_autofix_preview", descriptionFallback: "Preview the top verified BugHunter autofix.", properties: bugRunIdProps, required: ["run_id"]),
        workflowEntry(name: "bughunter_autofix_apply", descriptionFallback: "Apply the top verified BugHunter autofix.", properties: bugRunIdProps, required: ["run_id"]),
        workflowEntry(name: "bughunter_autofix_commit", descriptionFallback: "Apply and commit the top verified BugHunter autofix.", properties: bugRunIdProps, required: ["run_id"]),
        workflowEntry(name: "bughunter_explain_cluster", descriptionFallback: "Explain the strongest BugHunter defect cluster.", properties: bugRunIdProps, required: ["run_id"]),
        workflowEntry(name: "bughunter_cancel_run", descriptionFallback: "Cancel an in-flight BugHunter run.", properties: bugRunIdProps, required: ["run_id"]),
        workflowEntry(
            name: "bughunter_commit_window",
            descriptionFallback: "Run BugHunter on a commit plus correlated history window.",
            properties: workflowStringProps([
                "git_root": ("Repository root.", nil),
                "primary_commit": ("Primary commit SHA.", nil),
                "conversation_id": ("Optional conversation UUID.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: ["git_root", "primary_commit"]
        ),
        workflowEntry(name: "bughunter_install_hook", descriptionFallback: "Install the managed post-commit BugHunter hook.", properties: workflowStringProps(["git_root": ("Repository root for hooks.", nil)]), required: ["git_root"]),
        workflowEntry(name: "bughunter_uninstall_hook", descriptionFallback: "Remove the managed BugHunter hook.", properties: workflowStringProps(["git_root": ("Repository root for hooks.", nil)]), required: ["git_root"]),
        workflowEntry(
            name: "bughunter_run_history",
            descriptionFallback: "List prior BugHunter runs with summaries.",
            properties: workflowStringProps([
                "conversation_id": ("Optional conversation filter.", nil),
                "conversationId": ("Alias of conversation_id.", nil),
            ]),
            required: []
        ),
    ]

    private static let sessionScopeProps = workflowStringProps([
        "session_id": ("Owning review or security session id.", nil),
        "sessionId": ("Alias of session_id.", nil),
        "conversation_id": ("Conversation UUID for scoped sessions.", nil),
        "conversationId": ("Alias of conversation_id.", nil),
    ])

    private static let findingPatchProps = workflowStringProps([
        "finding_id": ("Finding id in the VerifiedFindings snapshot.", nil),
        "session_id": ("Session that owns the finding.", nil),
        "sessionId": ("Alias of session_id.", nil),
        "conversation_id": ("Conversation UUID when sessions are scoped.", nil),
        "conversationId": ("Alias of conversation_id.", nil),
    ])

    private static let findingPatchRequired = ["finding_id", "session_id"]

    private static let bugRunIdProps = workflowStringProps([
        "run_id": ("BugHunter run id (required).", nil),
        "conversation_id": ("Optional conversation UUID.", nil),
        "conversationId": ("Alias of conversation_id.", nil),
    ])

    private static func workflowPatchEntry(
        name: String,
        descriptionFallback: String
    ) -> ToolSchemaEntry {
        workflowEntry(
            name: name,
            descriptionFallback: descriptionFallback,
            properties: findingPatchProps,
            required: findingPatchRequired
        )
    }

    private static func workflowEntry(
        name: String,
        descriptionFallback: String,
        properties: [String: [String: Any]],
        required: [String]
    ) -> ToolSchemaEntry {
        let description = CoderIDECanonicalToolRegistry.shared.record(forRuntimeName: name)?.description
            ?? descriptionFallback
        return ToolSchemaEntry(
            name: name,
            description: description,
            properties: properties,
            required: required
        )
    }

    private static func workflowStringProps(
        _ specs: [String: (description: String, values: [String]?)]
    ) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for (key, spec) in specs {
            var prop: [String: Any] = [
                "type": "string",
                "description": spec.description,
            ]
            if let values = spec.values {
                prop["enum"] = values
            }
            result[key] = prop
        }
        return result
    }
}
