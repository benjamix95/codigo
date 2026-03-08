import CoderEngine
import Foundation
import MCP

extension CoderIDETools {
    static let auditTools: [Tool] = [
        Tool(
            name: "coderide_\(ReviewAuditToolName.securitySecrets)",
            description: "Scan scoped files for hardcoded secrets and credential leaks.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Audit Security Secrets", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_\(ReviewAuditToolName.securityDependencies)",
            description: "Run a structured dependency security audit for supported package managers.",
            inputSchema: .object(["type": "object", "properties": .object([:])]),
            annotations: .init(title: "Audit Security Dependencies", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_\(ReviewAuditToolName.securityPatterns)",
            description: "Scan scoped files for insecure code patterns and policy violations.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Audit Security Patterns", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_\(ReviewAuditToolName.bugDiffRisks)",
            description: "Scan scoped files for crash risks, deadlocks, and regression-prone code patterns.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Audit Bug Diff Risks", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_\(ReviewAuditToolName.bugTestGaps)",
            description: "Detect likely test coverage gaps for changed source files.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Audit Bug Test Gaps", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_\(ReviewAuditToolName.bugHotspots)",
            description: "Identify scoped files that are recent change hotspots and regression risks.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope_files": .object([
                        "type": "string",
                        "description": "Optional JSON array or comma-separated list of scoped files.",
                    ]),
                    "path": .object([
                        "type": "string",
                        "description": "Optional file or directory scope.",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Audit Bug Hotspots", readOnlyHint: true, idempotentHint: true)
        ),
    ]
}
