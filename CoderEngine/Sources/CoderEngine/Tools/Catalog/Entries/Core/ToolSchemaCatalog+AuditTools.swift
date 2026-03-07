import Foundation

extension ToolSchemaCatalog {
    static let auditTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: ReviewAuditToolName.securitySecrets,
            description: "Scan scoped files for hardcoded secrets and credential leaks",
            properties: [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: ReviewAuditToolName.securityDependencies,
            description: "Run a structured security dependency audit for supported package managers",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: ReviewAuditToolName.securityPatterns,
            description: "Scan scoped files for insecure code patterns and policy violations",
            properties: [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: ReviewAuditToolName.bugDiffRisks,
            description: "Scan scoped files for crash risks, deadlocks, and regression-prone code patterns",
            properties: [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: ReviewAuditToolName.bugTestGaps,
            description: "Detect likely test coverage gaps for changed source files",
            properties: [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: ReviewAuditToolName.bugHotspots,
            description: "Identify scoped files that are recent change hotspots and regression risks",
            properties: [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: []
        ),
    ]
}
