import Foundation
import MCP

extension CoderIDETools {
    static let bugHunterTools: [Tool] = [
        Tool(
            name: "coderide_bughunter_start",
            description: "Start a BugHunter run on uncommitted files, a commit, a commit window, or a branch window.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "source_kind": .object(["type": "string", "description": "uncommitted, commit, commit_window, branch_window"]),
                    "git_root": .object(["type": "string", "description": "Repository root path"]),
                    "primary_commit": .object(["type": "string", "description": "Primary commit SHA when source_kind is commit or commit_window"]),
                    "branch_name": .object(["type": "string", "description": "Branch name for branch_window runs"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "BugHunter Start", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_status",
            description: "Read current BugHunter run status and linked review status.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "BugHunter Status", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_bughunter_findings",
            description: "Read findings for a BugHunter run through its linked review session.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "kind": .object(["type": "string", "description": "verified or candidate"]),
                    "severity": .object(["type": "string", "description": "critical, warning, suggestion, info"]),
                    "status": .object(["type": "string", "description": "Optional status filter"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "BugHunter Findings", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_bughunter_autofix_preview",
            description: "Prepare autofix preview for the highest-confidence verified BugHunter finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("run_id")]),
            ]),
            annotations: .init(title: "BugHunter Autofix Preview", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_autofix_apply",
            description: "Apply autofix for the highest-confidence verified BugHunter finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("run_id")]),
            ]),
            annotations: .init(title: "BugHunter Autofix Apply", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_autofix_commit",
            description: "Apply and commit autofix for the highest-confidence verified BugHunter finding, then queue re-review.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("run_id")]),
            ]),
            annotations: .init(title: "BugHunter Autofix Commit", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_commit_window",
            description: "Start a BugHunter run on a commit plus correlated prior commits.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "git_root": .object(["type": "string", "description": "Repository root path"]),
                    "primary_commit": .object(["type": "string", "description": "Primary commit SHA"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("git_root"), .string("primary_commit")]),
            ]),
            annotations: .init(title: "BugHunter Commit Window", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_install_hook",
            description: "Install the managed post-commit hook that triggers BugHunter asynchronously.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "git_root": .object(["type": "string", "description": "Repository root path"]),
                ]),
                "required": .array([.string("git_root")]),
            ]),
            annotations: .init(title: "BugHunter Install Hook", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_uninstall_hook",
            description: "Remove the managed post-commit hook for BugHunter.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "git_root": .object(["type": "string", "description": "Repository root path"]),
                ]),
                "required": .array([.string("git_root")]),
            ]),
            annotations: .init(title: "BugHunter Uninstall Hook", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_bughunter_run_history",
            description: "List BugHunter runs and their outcome summary.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "BugHunter History", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_bughunter_explain_cluster",
            description: "Explain the top correlated bug cluster for a BugHunter run.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("run_id")]),
            ]),
            annotations: .init(title: "BugHunter Explain Cluster", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_bughunter_cancel_run",
            description: "Cancel a running BugHunter run.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "run_id": .object(["type": "string", "description": "BugHunter run id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("run_id")]),
            ]),
            annotations: .init(title: "BugHunter Cancel Run", readOnlyHint: false)
        ),
    ]
}
