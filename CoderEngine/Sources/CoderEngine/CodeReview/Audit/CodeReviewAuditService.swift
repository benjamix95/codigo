import Foundation

public enum CodeReviewAuditService {
    public static func runTool(
        named toolName: String,
        scopeFiles: [String],
        workspacePath: URL
    ) -> ReviewAuditToolResult {
        let startedAt = Date()
        let scopedFiles = scopedExistingFiles(scopeFiles, workspacePath: workspacePath)

        let result: ReviewAuditToolResult
        switch toolName {
        case ReviewAuditToolName.securitySecrets:
            let raw = runSecuritySecretsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.securityDependencies:
            let raw = runSecurityDependenciesAudit(workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.securityPatterns:
            let raw = runSecurityPatternsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.securityDataflow:
            let raw = runSecurityDataflowAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.securityAuthz:
            let raw = runSecurityAuthzAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.securityCrypto:
            let raw = runSecurityCryptoAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.securityDeserialization:
            let raw = runSecurityDeserializationAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.securitySurface:
            let raw = runSecuritySurfaceAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.securitySupplyChain:
            let raw = runSecuritySupplyChainAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugDiffRisks:
            let raw = runBugDiffRisksAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.bugTestGaps:
            let raw = runBugTestGapsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.bugHotspots:
            let raw = runBugHotspotsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary)
        case ReviewAuditToolName.bugNilCrashPaths:
            let raw = runBugNilCrashPathsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugStateMachine:
            let raw = runBugStateMachineAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugConcurrency:
            let raw = runBugConcurrencyAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugErrorHandling:
            let raw = runBugErrorHandlingAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugAPIContracts:
            let raw = runBugAPIContractsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugTestImpact:
            let raw = runBugTestImpactAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugDependencyDrift:
            let raw = runBugDependencyDriftAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.bugDiffSemantics:
            let raw = runBugDiffSemanticsAudit(scopeFiles: scopedFiles, workspacePath: workspacePath)
            result = ReviewAuditToolResult(toolName: toolName, findings: raw.findings, durationMs: 0, coverageAvailable: raw.coverageAvailable, summary: raw.summary, adaptersUsed: raw.adapters, verificationHints: [raw.metadata["verification_hint"] ?? ""], metadata: raw.metadata)
        case ReviewAuditToolName.runProfile:
            let profileName = ReviewAuditProfile(rawValue: scopeFiles.first ?? "") ?? .quick
            let profileResults = runProfile(named: profileName, scopeFiles: scopedFiles.dropFirst().map { $0 }, workspacePath: workspacePath)
            result = correlateResults(profileResults, summaryPrefix: "audit_run_profile.\(profileName.rawValue)")
        case ReviewAuditToolName.correlateFindings:
            let correlated = correlateResults(
                runProfile(named: .quick, scopeFiles: scopedFiles, workspacePath: workspacePath),
                summaryPrefix: "audit_correlate_findings"
            )
            result = correlated
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
            let explanation = scopedFiles.first ?? "No finding context provided."
            result = ReviewAuditToolResult(
                toolName: toolName,
                findings: [],
                durationMs: 0,
                coverageAvailable: true,
                summary: explanation,
                metadata: ["signal_type": "manual", "verification_hint": "explanation_only", "promotion_gate": "none"]
            )
        default:
            result = ReviewAuditToolResult(
                toolName: toolName,
                findings: [],
                durationMs: 0,
                coverageAvailable: false,
                summary: "Unsupported audit tool: \(toolName)"
            )
        }

        return ReviewAuditToolResult(
            toolName: toolName,
            findings: deduplicate(result.findings),
            durationMs: max(1, Int(Date().timeIntervalSince(startedAt) * 1000)),
            coverageAvailable: result.coverageAvailable,
            summary: result.summary,
            adaptersUsed: result.adaptersUsed,
            verificationHints: result.verificationHints,
            metadata: result.metadata,
            clusters: result.clusters
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
