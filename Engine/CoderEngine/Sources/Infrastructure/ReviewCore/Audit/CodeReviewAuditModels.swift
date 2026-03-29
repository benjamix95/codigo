import Foundation

public enum ReviewAuditToolName {
    public static let securitySecrets = "audit_security_secrets"
    public static let securityDependencies = "audit_security_dependencies"
    public static let securityPatterns = "audit_security_patterns"
    public static let securityDataflow = "audit_security_dataflow"
    public static let securityAuthz = "audit_security_authz"
    public static let securityCrypto = "audit_security_crypto"
    public static let securityDeserialization = "audit_security_deserialization"
    public static let securitySurface = "audit_security_surface"
    public static let securitySupplyChain = "audit_security_supply_chain"
    public static let bugDiffRisks = "audit_bug_diff_risks"
    public static let bugTestGaps = "audit_bug_test_gaps"
    public static let bugHotspots = "audit_bug_hotspots"
    public static let bugNilCrashPaths = "audit_bug_nil_crash_paths"
    public static let bugStateMachine = "audit_bug_state_machine"
    public static let bugConcurrency = "audit_bug_concurrency"
    public static let bugErrorHandling = "audit_bug_error_handling"
    public static let bugAPIContracts = "audit_bug_api_contracts"
    public static let bugTestImpact = "audit_bug_test_impact"
    public static let bugDependencyDrift = "audit_bug_dependency_drift"
    public static let bugDiffSemantics = "audit_bug_diff_semantics"

    // MARK: - Performance Tools

    public static let perfBottlenecks = "audit_perf_bottlenecks"
    public static let perfMemory = "audit_perf_memory"
    public static let perfUIResponsiveness = "audit_perf_ui_responsiveness"
    public static let perfStartup = "audit_perf_startup"
    public static let perfHotPaths = "audit_perf_hot_paths"
    public static let perfCorrelate = "audit_perf_correlate"
    public static let perfTrending = "audit_perf_trending"

    public static let runProfile = "audit_run_profile"
    public static let correlateFindings = "audit_correlate_findings"
    public static let verifyBundle = "audit_verify_bundle"
    public static let explainFinding = "audit_explain_finding"

    public static let securityTools = [
        securitySecrets,
        securityDependencies,
        securityPatterns,
        securityDataflow,
        securityAuthz,
        securityCrypto,
        securityDeserialization,
        securitySurface,
        securitySupplyChain,
    ]

    public static let bugTools = [
        bugDiffRisks,
        bugTestGaps,
        bugHotspots,
        bugNilCrashPaths,
        bugStateMachine,
        bugConcurrency,
        bugErrorHandling,
        bugAPIContracts,
        bugTestImpact,
        bugDependencyDrift,
        bugDiffSemantics,
    ]

    public static let performanceTools = [
        perfBottlenecks,
        perfMemory,
        perfUIResponsiveness,
        perfStartup,
        perfHotPaths,
    ]

    public static let performanceAdvancedTools = [
        perfCorrelate,
        perfTrending,
    ]

    public static let metaTools = [
        runProfile,
        correlateFindings,
        verifyBundle,
        explainFinding,
    ]

    public static let all = securityTools + bugTools + performanceTools
    public static let allToolNames = all + performanceAdvancedTools + metaTools
}

public enum ReviewAuditProfile: String, Sendable, Codable, CaseIterable {
    case quick
    case securityDeep = "security_deep"
    case bugHuntDeep = "bug_hunt_deep"
    case performanceDeep = "performance_deep"
    case releaseGate = "release_gate"
    case iosPreflight = "ios_preflight"
    case backendRegression = "backend_regression"
}

public struct ReviewAuditCorrelationCluster: Sendable, Codable, Equatable {
    public let id: String
    public let title: String
    public let files: [String]
    public let findingIDs: [String]
    public let confidence: Double

    public init(
        id: String,
        title: String,
        files: [String],
        findingIDs: [String],
        confidence: Double
    ) {
        self.id = id
        self.title = title
        self.files = files
        self.findingIDs = findingIDs
        self.confidence = confidence
    }
}

public struct ReviewAuditToolResult: Sendable, Codable {
    public let toolName: String
    public let findings: [CodeReviewFinding]
    public let durationMs: Int
    public let coverageAvailable: Bool
    public let summary: String
    public let adaptersUsed: [String]
    public let verificationHints: [String]
    public let metadata: [String: String]
    public let clusters: [ReviewAuditCorrelationCluster]

    public init(
        toolName: String,
        findings: [CodeReviewFinding],
        durationMs: Int,
        coverageAvailable: Bool,
        summary: String,
        adaptersUsed: [String] = [],
        verificationHints: [String] = [],
        metadata: [String: String] = [:],
        clusters: [ReviewAuditCorrelationCluster] = []
    ) {
        self.toolName = toolName
        self.findings = findings
        self.durationMs = durationMs
        self.coverageAvailable = coverageAvailable
        self.summary = summary
        self.adaptersUsed = adaptersUsed
        self.verificationHints = verificationHints
        self.metadata = metadata
        self.clusters = clusters
    }

    public var blockingFindingsCount: Int {
        findings.filter(\.blocking).count
    }

    public var payload: ReviewAuditToolPayload {
        ReviewAuditToolPayload(
            tool: toolName,
            findings: findings.map { ReviewAuditFindingPayload($0, result: self) },
            summary: summary,
            coverageAvailable: coverageAvailable,
            durationMs: durationMs,
            adaptersUsed: adaptersUsed,
            verificationHints: verificationHints,
            metadata: metadata,
            clusters: clusters
        )
    }
}

public struct ReviewAuditToolPayload: Sendable, Codable {
    public let tool: String
    public let findings: [ReviewAuditFindingPayload]
    public let summary: String
    public let coverageAvailable: Bool
    public let durationMs: Int
    public let adaptersUsed: [String]
    public let verificationHints: [String]
    public let metadata: [String: String]
    public let clusters: [ReviewAuditCorrelationCluster]
}

public struct ReviewAuditFindingPayload: Sendable, Codable {
    public let severity: String
    public let category: String
    public let origin: String
    public let file: String
    public let line: Int?
    public let confidence: Double?
    public let evidence: String?
    public let remediation: String?
    public let sourceTool: String?
    public let blocking: Bool
    public let signalType: String?
    public let verificationHint: String?
    public let evidenceKind: String?
    public let secondarySources: [String]
    public let confidenceComponents: [String: Double]
    public let promotionGate: String?
    public let relatedSymbols: [String]
    public let relatedTests: [String]
    public let behavioralImpact: String?

    public init(
        _ finding: CodeReviewFinding,
        result: ReviewAuditToolResult
    ) {
        severity = finding.severity.rawValue
        category = finding.category.rawValue
        origin = finding.origin.rawValue
        file = finding.filePath
        line = finding.lineNumber
        confidence = finding.confidence
        evidence = finding.evidence
        remediation = finding.suggestedFix
        sourceTool = finding.sourceTool
        blocking = finding.blocking
        signalType = result.metadata["signal_type"] ?? Self.inferSignalType(toolName: finding.sourceTool ?? result.toolName)
        verificationHint = result.metadata["verification_hint"]
        evidenceKind = result.metadata["evidence_kind"] ?? Self.inferEvidenceKind(finding.evidence)
        secondarySources = result.adaptersUsed
        confidenceComponents = Self.makeConfidenceComponents(finding: finding, result: result)
        promotionGate = result.metadata["promotion_gate"] ?? "strict_verified"
        relatedSymbols = Self.extractCSV(result.metadata["related_symbols"])
        relatedTests = Self.extractCSV(result.metadata["related_tests"])
        behavioralImpact = result.metadata["behavioral_impact"]
    }

    private static func inferSignalType(toolName: String) -> String {
        if toolName.contains("semantic") || toolName.contains("dataflow") || toolName.contains("authz") {
            return "semantic"
        }
        if toolName.contains("test") {
            return "test_derived"
        }
        return "pattern"
    }

    private static func inferEvidenceKind(_ evidence: String?) -> String {
        guard let evidence, !evidence.isEmpty else { return "none" }
        if evidence.contains("git") || evidence.contains("diff") {
            return "diff"
        }
        if evidence.contains(":") || evidence.contains("(") {
            return "code"
        }
        return "text"
    }

    private static func makeConfidenceComponents(
        finding: CodeReviewFinding,
        result: ReviewAuditToolResult
    ) -> [String: Double] {
        var components: [String: Double] = [:]
        if let confidence = finding.confidence {
            components["primary_signal"] = confidence
        }
        if !result.adaptersUsed.isEmpty {
            components["adapter_support"] = 0.15
        }
        if finding.evidence?.isEmpty == false {
            components["local_evidence"] = 0.20
        }
        if finding.blocking {
            components["policy_weight"] = 0.10
        }
        return components
    }

    private static func extractCSV(_ raw: String?) -> [String] {
        (raw ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
