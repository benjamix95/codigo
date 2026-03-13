import Foundation

public enum CodeReviewAuditService {
    public static func runTool(
        named toolName: String,
        scopeFiles: [String],
        workspacePath: URL
    ) -> ReviewAuditToolResult {
        let rawScopeFiles = scopeFiles.map(normalizedRelativePath)
        let startedAt = Date()
        let scopedFiles = scopedExistingFiles(scopeFiles, workspacePath: workspacePath)
        let result: ReviewAuditToolResult
        switch toolName {
        case ReviewAuditToolName.runProfile:
            let profileName = ReviewAuditProfile(rawValue: scopeFiles.first ?? "") ?? .quick
            let profileResults = runProfile(named: profileName, scopeFiles: scopedFiles.dropFirst().map { $0 }, workspacePath: workspacePath)
            result = correlateResults(profileResults, summaryPrefix: "audit_run_profile.\(profileName.rawValue)")
        case ReviewAuditToolName.correlateFindings:
            result = correlateResults(
                runProfile(named: .quick, scopeFiles: scopedFiles, workspacePath: workspacePath),
                summaryPrefix: "audit_correlate_findings"
            )
        case ReviewAuditToolName.verifyBundle:
            let correlated = correlateResults(
                runProfile(named: .securityDeep, scopeFiles: scopedFiles, workspacePath: workspacePath)
                    + runProfile(named: .bugHuntDeep, scopeFiles: scopedFiles, workspacePath: workspacePath),
                summaryPrefix: "audit_verify_bundle"
            )
            let strictFindings = correlated.findings.filter { ($0.confidence ?? 0) >= 0.75 || $0.blocking }
            result = ReviewAuditToolResult(
                toolName: toolName,
                findings: strictFindings,
                durationMs: correlated.durationMs,
                coverageAvailable: correlated.coverageAvailable,
                summary: "audit_verify_bundle: \(strictFindings.count) verified-grade finding(s).",
                adaptersUsed: correlated.adaptersUsed,
                verificationHints: correlated.verificationHints,
                metadata: correlated.metadata,
                clusters: correlated.clusters
            )
        case ReviewAuditToolName.explainFinding:
            let explanation = rawScopeFiles.first ?? "No finding context provided."
            result = ReviewAuditToolResult(
                toolName: toolName,
                findings: [],
                durationMs: 0,
                coverageAvailable: true,
                summary: explanation,
                metadata: ["signal_type": "manual", "verification_hint": "explanation_only", "promotion_gate": "none"]
            )
        default:
            result = bridgeAuditToolResult(
                named: toolName,
                scopeFiles: scopeFiles,
                workspacePath: workspacePath
            ) ?? unavailableAuditToolResult(toolName: toolName)
        }

        return ReviewAuditToolResult(
            toolName: toolName,
            findings: deduplicate(result.findings),
            durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
            coverageAvailable: result.coverageAvailable,
            summary: result.summary,
            adaptersUsed: result.adaptersUsed,
            verificationHints: result.verificationHints.filter { !$0.isEmpty },
            metadata: result.metadata,
            clusters: result.clusters
        )
    }

    private static func bridgeAuditToolResult(
        named toolName: String,
        scopeFiles: [String],
        workspacePath: URL
    ) -> ReviewAuditToolResult? {
        guard ReviewCoreBridge.isEnabled else { return nil }
        let request = ReviewCoreAuditRequest(
            schemaVersion: 1,
            toolName: toolName,
            scopeFiles: scopeFiles,
            workspacePath: workspacePath.path
        )
        let response: ReviewCoreAuditBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_run_audit",
            request: request
        )
        if let error = response?.error {
            return unsupportedAuditToolResult(toolName: toolName, error: error.code)
        }
        return response?.result
    }

    private static func unsupportedAuditToolResult(
        toolName: String,
        error: String
    ) -> ReviewAuditToolResult {
        ReviewAuditToolResult(
            toolName: toolName,
            findings: [],
            durationMs: 0,
            coverageAvailable: false,
            summary: "Unsupported audit tool in Rust review core: \(toolName) (\(error))"
        )
    }

    private static func unavailableAuditToolResult(
        toolName: String
    ) -> ReviewAuditToolResult {
        ReviewAuditToolResult(
            toolName: toolName,
            findings: [],
            durationMs: 0,
            coverageAvailable: false,
            summary: "Rust review core unavailable for audit tool: \(toolName)"
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
                finding.lineNumber.map(String.init) ?? "nil",
                finding.message.lowercased(),
            ].joined(separator: "|")
            if seen.insert(key).inserted {
                output.append(finding)
            }
        }
        return output
    }
}

private struct ReviewCoreAuditRequest: Encodable {
    let schemaVersion: Int
    let toolName: String
    let scopeFiles: [String]
    let workspacePath: String
}

private struct ReviewCoreAuditBridgeResponse: Decodable {
    let error: RustFFIErrorPayload?
    let result: ReviewAuditToolResult?
}
