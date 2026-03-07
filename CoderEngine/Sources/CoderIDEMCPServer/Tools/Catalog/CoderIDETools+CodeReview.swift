import Foundation
import MCP

extension CoderIDETools {
    static let codeReviewTools: [Tool] = [
        // --- Code Review Tools ---
        Tool(
            name: "coderide_review_start",
            description: """
                Start a code review session. Specify the scope (uncommitted, staged, or against a git ref) \
                and optional configuration for workers and rounds.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope": .object([
                        "type": "string",
                        "description": "Review scope: uncommitted (default), staged, or against_ref",
                    ]),
                    "ref": .object([
                        "type": "string",
                        "description": "Git ref to compare against (e.g. main, HEAD~3). Required when scope=against_ref.",
                    ]),
                    "max_workers": .object([
                        "type": "integer",
                        "description": "Max parallel fix workers (1-12, default 6)",
                    ]),
                    "max_rounds": .object([
                        "type": "integer",
                        "description": "Max review rounds (1-10, default 3)",
                    ]),
                    "analysis_only": .object([
                        "type": "boolean",
                        "description": "Run analysis only without fix/test rounds.",
                    ]),
                    "analysis_backend": .object([
                        "type": "string",
                        "description": "Backend for analysis phase (default: codex)",
                    ]),
                    "execution_backend": .object([
                        "type": "string",
                        "description": "Backend for execution phase (default: codex)",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "Optional custom session id for a new review session. Must be unique.",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Optional conversation UUID used to scope concurrent review sessions.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Review Start", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_list_sessions",
            description: "List code review sessions for the current conversation or across the workspace, including completed sessions.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Optional conversation UUID used to filter review sessions.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Review Sessions", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_review_status",
            description: "Get the current status of the active code review session: phase, progress, active workers, round info.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "session_id": .object([
                        "type": "string",
                        "description": "Optional session id to read. Required when multiple sessions are active.",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Optional conversation UUID used to resolve the active session.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Review Status", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_review_findings",
            description: "List code review findings. Filter by severity, file, or status.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "severity": .object([
                        "type": "string",
                        "description": "Filter by severity: critical, warning, suggestion, info",
                    ]),
                    "file": .object([
                        "type": "string",
                        "description": "Filter by file path (substring match)",
                    ]),
                    "status": .object([
                        "type": "string",
                        "description": "Filter by status: open, fix_applied, dismissed, wont_fix",
                    ]),
                    "limit": .object([
                        "type": "integer",
                        "description": "Max results (default: 50)",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "Optional session id to read. Required when multiple sessions are active.",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Optional conversation UUID used to resolve the active session.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Review Findings", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_review_apply_fix",
            description: "Apply the suggested fix for a specific code review finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object([
                        "type": "string",
                        "description": "The ID of the finding to apply the fix for",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "The review session id that owns the finding",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Required for conversation-scoped sessions.",
                    ]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Apply Fix", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_dismiss",
            description: "Dismiss a code review finding as false positive or won't fix.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object([
                        "type": "string",
                        "description": "The ID of the finding to dismiss",
                    ]),
                    "reason": .object([
                        "type": "string",
                        "description": "Reason for dismissal (e.g. false_positive, wont_fix, by_design)",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "The review session id that owns the finding",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Required for conversation-scoped sessions.",
                    ]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Dismiss", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_configure",
            description: "Update the runtime configuration for the active code review session.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "max_workers": .object([
                        "type": "integer",
                        "description": "Max parallel fix workers (1-12)",
                    ]),
                    "max_rounds": .object([
                        "type": "integer",
                        "description": "Max review rounds (1-10)",
                    ]),
                    "analysis_backend": .object([
                        "type": "string",
                        "description": "Backend for analysis phase",
                    ]),
                    "execution_backend": .object([
                        "type": "string",
                        "description": "Backend for execution phase",
                    ]),
                    "analysis_only": .object([
                        "type": "boolean",
                        "description": "Toggle analysis-only mode for this review session.",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "The review session id to update",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Required for conversation-scoped sessions.",
                    ]),
                ]),
                "required": .array([.string("session_id")]),
            ]),
            annotations: .init(title: "Review Configure", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_diff_summary",
            description: "Get a structured summary of the diff for files in the current review scope.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "file": .object([
                        "type": "string",
                        "description": "Optional specific file to get diff for. Returns all files if omitted.",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "Optional session id to read. Required when multiple sessions are active.",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Optional conversation UUID used to resolve the active session.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Review Diff Summary", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_review_comment",
            description: "Add a comment or annotation to a specific code review finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object([
                        "type": "string",
                        "description": "The ID of the finding to comment on",
                    ]),
                    "content": .object([
                        "type": "string",
                        "description": "The comment text",
                    ]),
                    "author": .object([
                        "type": "string",
                        "description": "Comment author (default: agent)",
                    ]),
                    "session_id": .object([
                        "type": "string",
                        "description": "The review session id that owns the finding",
                    ]),
                    "conversation_id": .object([
                        "type": "string",
                        "description": "Required for conversation-scoped sessions.",
                    ]),
                ]),
                "required": .array([.string("finding_id"), .string("content"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Comment", readOnlyHint: false)
        ),
    ]
}
