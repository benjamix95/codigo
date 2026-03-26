import Foundation
import MCP

extension CoderIDETools {
    static let securityWorkflowTools: [Tool] = [
        Tool(
            name: "coderide_security_start",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_start", fallback: "Start a security-focused review session."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_status", fallback: "Read the shared security review status."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_findings", fallback: "List security findings from the review session."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_verify_finding", fallback: "Verify a security finding before promoting it."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_prepare_patch", fallback: "Prepare a patch for a verified security finding."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_preview_patch", fallback: "Preview the prepared patch artifact for a security finding."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_apply_patch", fallback: "Apply a verified patch for a security finding."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_verify_patch", fallback: "Run patch validation for a prepared security patch."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_revalidate_finding", fallback: "Re-run post-fix validation for a security finding."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_rollback_patch", fallback: "Rollback an applied security patch."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_security_close_finding", fallback: "Close a security finding when fixed or rejected."),
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
