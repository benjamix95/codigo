import Foundation

extension ToolSchemaCatalog {
    static let auditTools: [ToolSchemaEntry] = [
        auditEntry(ReviewAuditToolName.securitySecrets, "Scan scoped files for hardcoded secrets and credential leaks"),
        auditEntry(ReviewAuditToolName.securityDependencies, "Run a structured security dependency audit for supported package managers"),
        auditEntry(ReviewAuditToolName.securityPatterns, "Scan scoped files for insecure code patterns and policy violations"),
        auditEntry(ReviewAuditToolName.securityDataflow, "Detect suspicious source-to-sink security flows in scoped files"),
        auditEntry(ReviewAuditToolName.securityAuthz, "Identify authorization gaps in routes, handlers, and surface files"),
        auditEntry(ReviewAuditToolName.securityCrypto, "Flag weak hashing, token generation, and crypto primitives"),
        auditEntry(ReviewAuditToolName.securityDeserialization, "Analyze risky parsing, eval, and unsafe deserialization patterns"),
        auditEntry(ReviewAuditToolName.securitySurface, "Map risky runtime surface such as ATS relaxations, webviews, and debug flags"),
        auditEntry(ReviewAuditToolName.securitySupplyChain, "Run hybrid internal plus optional external supply-chain audit"),
        auditEntry(ReviewAuditToolName.bugDiffRisks, "Scan scoped files for crash risks, deadlocks, and regression-prone code patterns"),
        auditEntry(ReviewAuditToolName.bugTestGaps, "Detect likely test coverage gaps for changed source files"),
        auditEntry(ReviewAuditToolName.bugHotspots, "Identify scoped files that are recent change hotspots and regression risks"),
        auditEntry(ReviewAuditToolName.bugNilCrashPaths, "Detect realistic nil, cast, indexing, and crash paths"),
        auditEntry(ReviewAuditToolName.bugStateMachine, "Analyze suspicious state transitions and state machine drift"),
        auditEntry(ReviewAuditToolName.bugConcurrency, "Detect risky concurrency, deadlock, and isolation patterns"),
        auditEntry(ReviewAuditToolName.bugErrorHandling, "Detect swallowed errors, weak fallbacks, and silent failure handling"),
        auditEntry(ReviewAuditToolName.bugAPIContracts, "Detect API and contract smells in public surfaces"),
        auditEntry(ReviewAuditToolName.bugTestImpact, "Map changed symbols to tests and flag regression impact gaps"),
        auditEntry(ReviewAuditToolName.bugDependencyDrift, "Flag dependency drift and lockfile changes with regression risk"),
        auditEntry(ReviewAuditToolName.bugDiffSemantics, "Compare textual diff with semantic change signals to reduce cosmetic noise"),
        auditEntry(ReviewAuditToolName.perfBottlenecks, "Detect blocking calls, sleeps, and main-thread bottlenecks in scoped files"),
        auditEntry(ReviewAuditToolName.perfMemory, "Detect memory-retention risks, cache misuse, and heavy resource patterns"),
        auditEntry(ReviewAuditToolName.perfUIResponsiveness, "Detect UI-thread blocking work and responsiveness regressions"),
        auditEntry(ReviewAuditToolName.perfStartup, "Detect eager startup work, constructors, and launch-time regressions"),
        auditEntry(ReviewAuditToolName.perfHotPaths, "Detect hot paths using churn, complexity, and nested-loop signals"),
        auditEntry(ReviewAuditToolName.runProfile, "Run a predefined audit profile and aggregate its findings", properties: [
            "profile": ["type": "string", "description": "quick, security_deep, bug_hunt_deep, performance_deep, performance_extended, performance_full, release_gate, ios_preflight, backend_regression"],
            "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
            "path": ["type": "string", "description": "Optional file or directory scope"]
        ], required: ["profile"]),
        auditEntry(ReviewAuditToolName.correlateFindings, "Run multi-signal audit correlation across the scoped files"),
        auditEntry(ReviewAuditToolName.verifyBundle, "Run strict verification-grade audit bundle across the scoped files"),
        auditEntry(ReviewAuditToolName.explainFinding, "Explain one finding in concise machine-readable form", properties: [
            "file": ["type": "string", "description": "File path associated with the finding"],
            "message": ["type": "string", "description": "Finding message to explain"],
            "line": ["type": "integer", "description": "Optional line number"],
            "evidence": ["type": "string", "description": "Optional evidence excerpt"]
        ], required: ["file", "message"]),
    ]

    private static func auditEntry(
        _ name: String,
        _ description: String,
        properties: [String: [String: Any]]? = nil,
        required: [String] = []
    ) -> ToolSchemaEntry {
        ToolSchemaEntry(
            name: name,
            description: description,
            properties: properties ?? [
                "scope_files": ["type": "string", "description": "Optional JSON array or comma-separated list of scoped files"],
                "path": ["type": "string", "description": "Optional file or directory scope"]
            ],
            required: required
        )
    }
}
