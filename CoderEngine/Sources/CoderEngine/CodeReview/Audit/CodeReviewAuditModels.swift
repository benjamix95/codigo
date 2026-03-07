import Foundation

public enum ReviewAuditToolName {
    public static let securitySecrets = "audit_security_secrets"
    public static let securityDependencies = "audit_security_dependencies"
    public static let securityPatterns = "audit_security_patterns"
    public static let bugDiffRisks = "audit_bug_diff_risks"
    public static let bugTestGaps = "audit_bug_test_gaps"
    public static let bugHotspots = "audit_bug_hotspots"

    public static let securityTools = [
        securitySecrets,
        securityDependencies,
        securityPatterns,
    ]

    public static let bugTools = [
        bugDiffRisks,
        bugTestGaps,
        bugHotspots,
    ]

    public static let all = securityTools + bugTools
}

public struct ReviewAuditToolResult: Sendable, Codable {
    public let toolName: String
    public let findings: [CodeReviewFinding]
    public let durationMs: Int
    public let coverageAvailable: Bool
    public let summary: String

    public init(
        toolName: String,
        findings: [CodeReviewFinding],
        durationMs: Int,
        coverageAvailable: Bool,
        summary: String
    ) {
        self.toolName = toolName
        self.findings = findings
        self.durationMs = durationMs
        self.coverageAvailable = coverageAvailable
        self.summary = summary
    }

    public var blockingFindingsCount: Int {
        findings.filter(\.blocking).count
    }

    public var payload: ReviewAuditToolPayload {
        ReviewAuditToolPayload(
            tool: toolName,
            findings: findings.map(ReviewAuditFindingPayload.init),
            summary: summary,
            coverageAvailable: coverageAvailable,
            durationMs: durationMs
        )
    }
}

public struct ReviewAuditToolPayload: Sendable, Codable {
    public let tool: String
    public let findings: [ReviewAuditFindingPayload]
    public let summary: String
    public let coverageAvailable: Bool
    public let durationMs: Int
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

    public init(_ finding: CodeReviewFinding) {
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
    }
}
