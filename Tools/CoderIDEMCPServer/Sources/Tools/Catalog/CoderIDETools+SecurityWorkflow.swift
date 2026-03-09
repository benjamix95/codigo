import Foundation
import MCP

extension CoderIDETools {
    static let securityWorkflowTools: [Tool] = [
        Tool(
            name: "coderide_security_start",
            description: "Start a security-focused review session on uncommitted, staged, or against-ref scope using the shared VerifiedFindings backend.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope": .object(["type": "string", "description": "uncommitted, staged, against_ref"]),
                    "ref": .object(["type": "string", "description": "Git ref when scope=against_ref"]),
                    "session_id": .object(["type": "string", "description": "Optional unique session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "Security Start", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_status",
            description: "Read the shared security review status and security gate summary.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
            ]),
            annotations: .init(title: "Security Status", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_security_findings",
            description: "List security findings from the shared VerifiedFindings-backed review session.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                    "kind": .object(["type": "string", "description": "verified or candidate"]),
                    "severity": .object(["type": "string", "description": "critical, warning, suggestion, info"]),
                    "status": .object(["type": "string", "description": "Optional status filter"]),
                ]),
            ]),
            annotations: .init(title: "Security Findings", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_security_verify_finding",
            description: "Verify a security finding before promoting it to the verified queue.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Verify Finding", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_prepare_patch",
            description: "Prepare a patch for a verified security finding using the shared review workflow.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Prepare Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_preview_patch",
            description: "Preview the prepared patch artifact for a security finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Preview Patch", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_security_apply_patch",
            description: "Apply a verified patch for a security finding and reuse the shared revalidation flow.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Apply Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_verify_patch",
            description: "Run patch validation for a prepared security patch artifact.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Verify Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_revalidate_finding",
            description: "Re-run the shared post-fix validation flow for a security finding.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Revalidate Finding", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_rollback_patch",
            description: "Rollback an applied security patch through the shared review lifecycle.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Rollback Patch", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_security_close_finding",
            description: "Close a security finding when it is fixed, rejected, or manually resolved.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "finding_id": .object(["type": "string", "description": "Security finding id"]),
                    "session_id": .object(["type": "string", "description": "Security review session id"]),
                    "reason": .object(["type": "string", "description": "Closure reason"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("finding_id"), .string("session_id")]),
            ]),
            annotations: .init(title: "Security Close Finding", readOnlyHint: false)
        ),
    ]
}
