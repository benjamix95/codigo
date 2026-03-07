import Foundation

public enum CodeReviewAuditService {
    public static func runTool(
        named toolName: String,
        scopeFiles: [String],
        workspacePath: URL
    ) -> ReviewAuditToolResult {
        let startedAt = Date()
        let scopedFiles = scopedExistingFiles(scopeFiles, workspacePath: workspacePath)

        let result: (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String)
        switch toolName {
        case ReviewAuditToolName.securitySecrets:
            result = runSecuritySecretsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
        case ReviewAuditToolName.securityDependencies:
            result = runSecurityDependenciesAudit(workspacePath: workspacePath)
        case ReviewAuditToolName.securityPatterns:
            result = runSecurityPatternsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
        case ReviewAuditToolName.bugDiffRisks:
            result = runBugDiffRisksAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
        case ReviewAuditToolName.bugTestGaps:
            result = runBugTestGapsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
        case ReviewAuditToolName.bugHotspots:
            result = runBugHotspotsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
        default:
            result = (
                findings: [],
                coverageAvailable: false,
                summary: "Unsupported audit tool: \(toolName)"
            )
        }

        return ReviewAuditToolResult(
            toolName: toolName,
            findings: deduplicate(result.findings),
            durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
            coverageAvailable: result.coverageAvailable,
            summary: result.summary
        )
    }

    public static func runSecuritySuite(
        scopeFiles: [String],
        workspacePath: URL
    ) -> [ReviewAuditToolResult] {
        ReviewAuditToolName.securityTools.map {
            runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
        }
    }

    public static func runBugSuite(
        scopeFiles: [String],
        workspacePath: URL
    ) -> [ReviewAuditToolResult] {
        ReviewAuditToolName.bugTools.map {
            runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
        }
    }

    static func deduplicate(_ findings: [CodeReviewFinding]) -> [CodeReviewFinding] {
        var seen = Set<String>()
        var output: [CodeReviewFinding] = []
        for finding in findings {
            let key = [
                finding.origin.rawValue,
                finding.category.rawValue,
                finding.filePath,
                String(finding.lineNumber ?? 0),
                finding.message.lowercased(),
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                output.append(finding)
            }
        }
        return output
    }
}
