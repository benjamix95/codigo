import Foundation

extension CodeReviewAuditService {
    static func correlateFindings(_ findings: [CodeReviewFinding]) -> [ReviewAuditCorrelationCluster] {
        let groups = Dictionary(grouping: findings) { finding in
            let prefix = finding.message.split(separator: ".").first.map(String.init) ?? finding.message
            return "\(finding.category.rawValue)|\(prefix.lowercased())"
        }
        return groups.enumerated().map { index, element in
            let files = Array(Set(element.value.map(\.filePath))).sorted()
            let avgConfidence = element.value.compactMap(\.confidence).reduce(0, +) / Double(max(element.value.compactMap(\.confidence).count, 1))
            return ReviewAuditCorrelationCluster(
                id: "cluster-\(index + 1)",
                title: element.key.components(separatedBy: "|").last ?? "cluster",
                files: files,
                findingIDs: element.value.map(\.id),
                confidence: avgConfidence
            )
        }
        .sorted { $0.confidence > $1.confidence }
    }

    static func runProfile(
        named profile: ReviewAuditProfile,
        scopeFiles: [String],
        workspacePath: URL
    ) -> [ReviewAuditToolResult] {
        switch profile {
        case .quick:
            return [
                runTool(named: ReviewAuditToolName.securityPatterns, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffRisks, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugTestImpact, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .securityDeep:
            return ReviewAuditToolName.securityTools.map {
                runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
            }
        case .bugHuntDeep:
            return ReviewAuditToolName.bugTools.map {
                runTool(named: $0, scopeFiles: scopeFiles, workspacePath: workspacePath)
            }
        case .releaseGate:
            return [
                runTool(named: ReviewAuditToolName.securitySupplyChain, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffSemantics, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugTestImpact, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .iosPreflight:
            return [
                runTool(named: ReviewAuditToolName.securitySurface, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.securityCrypto, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugConcurrency, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        case .backendRegression:
            return [
                runTool(named: ReviewAuditToolName.securityDataflow, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugErrorHandling, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugAPIContracts, scopeFiles: scopeFiles, workspacePath: workspacePath),
                runTool(named: ReviewAuditToolName.bugDiffSemantics, scopeFiles: scopeFiles, workspacePath: workspacePath),
            ]
        }
    }

    static func correlateResults(
        _ results: [ReviewAuditToolResult],
        summaryPrefix: String
    ) -> ReviewAuditToolResult {
        let findings = deduplicate(results.flatMap(\.findings))
        let clusters = correlateFindings(findings)
        let adapters = Array(Set(results.flatMap(\.adaptersUsed))).sorted()
        let hints = Array(Set(results.flatMap(\.verificationHints))).sorted()
        let metadata: [String: String] = [
            "signal_type": "multi_signal",
            "verification_hint": hints.joined(separator: " | "),
            "promotion_gate": "strict_verified",
            "behavioral_impact": findings.contains(where: \.blocking) ? "high_risk" : "mixed",
        ]
        return ReviewAuditToolResult(
            toolName: ReviewAuditToolName.correlateFindings,
            findings: findings,
            durationMs: max(1, results.reduce(0) { $0 + $1.durationMs }),
            coverageAvailable: results.contains(where: \.coverageAvailable),
            summary: "\(summaryPrefix): \(findings.count) finding(s), \(clusters.count) cluster(s).",
            adaptersUsed: adapters,
            verificationHints: hints,
            metadata: metadata,
            clusters: clusters
        )
    }
}
