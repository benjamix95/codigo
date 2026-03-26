import Foundation
import MCP

extension CoderIDETools {
    static let codeReviewWorkflowTools: [Tool] = [
        Tool(
            name: "coderide_review_verify_finding",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_verify_finding", fallback: "Verify a review candidate or finding before promoting or patching it."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding or candidate id to verify"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Verify Finding", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_prepare_patch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_prepare_patch", fallback: "Prepare a concrete patch preview for a verified review finding."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Verified finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Prepare Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_preview_patch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_preview_patch", fallback: "Preview the stored patch artifact for a review finding."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Preview Patch", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_review_apply_patch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_apply_patch", fallback: "Apply the stored verified patch for a review finding."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Apply Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_verify_patch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_verify_patch", fallback: "Run dry-run verification for the stored patch of a review finding."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Verify Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_revalidate_finding",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_revalidate_finding", fallback: "Re-run post-fix validation for an already applied review patch."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Revalidate Finding", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_rollback_patch",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_rollback_patch", fallback: "Rollback an already applied review patch."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Rollback Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_close_finding",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_close_finding", fallback: "Close a review finding when the fix was verified."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "reason": .object(["type": "string", "description": "Closure reason"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Close Finding", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_open_pr",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_open_pr", fallback: "Open a PR for the stored patch artifact of a review finding."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Open PR", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_merge_pr",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_merge_pr", fallback: "Merge the PR associated with a review patch."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Merge PR", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_resolve_conflicts",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_resolve_conflicts", fallback: "Attempt safe automatic conflict resolution for the review patch branch."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Finding id"]),
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Review Resolve Conflicts", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_review_get_outcome",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_review_get_outcome", fallback: "Read the structured outcome summary for a review session."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "session_id": .object(["type": "string", "description": "Owning review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Conversation UUID for scoped sessions"]),
                ]),
                "required": .array([.string("session_id")]),
            ]),
            annotations: .init(title: "Review Outcome", readOnlyHint: true, idempotentHint: true)
        ),
    ]
}
