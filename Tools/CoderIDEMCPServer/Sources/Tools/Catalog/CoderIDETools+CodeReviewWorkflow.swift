import Foundation
import MCP

extension CoderIDETools {
    static let codeReviewWorkflowTools: [Tool] = [
        Tool(
            name: "coderide_review_verify_finding",
            description: "Verify a review candidate or finding before promoting or patching it.",
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
            description: "Prepare a concrete patch preview for a verified review finding.",
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
            description: "Preview the stored patch artifact for a review finding.",
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
            description: "Apply the stored verified patch for a review finding to the local workspace.",
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
            description: "Run dry-run verification for the stored patch of a review finding.",
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
            name: "coderide_review_open_pr",
            description: "Open a PR for the stored patch artifact of a review finding.",
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
            description: "Merge the PR associated with a review patch, using safe conflict handling when configured.",
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
            description: "Attempt a safe automatic conflict resolution for the PR patch branch of a review finding.",
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
            description: "Read the structured outcome summary for a review session.",
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
