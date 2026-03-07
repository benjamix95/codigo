import Foundation

extension CodeReviewAuditService {
    static func runSecuritySecretsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let patterns: [(needle: String, severity: FindingSeverity, message: String, remediation: String)] = [
            ("BEGIN PRIVATE KEY", .critical, "Private key material committed in source.", "Move the key to secure secret storage and rotate it immediately."),
            ("sk_live_", .critical, "Live secret token detected in source.", "Remove the credential from source control and rotate it immediately."),
            ("ghp_", .critical, "GitHub personal access token detected in source.", "Remove the token and rotate it immediately."),
            ("api_key", .warning, "Potential hardcoded API key detected.", "Move the secret to environment/config management."),
            ("access_token", .warning, "Potential hardcoded access token detected.", "Store the token outside source control."),
            ("client_secret", .warning, "Potential hardcoded client secret detected.", "Load the secret from secure runtime configuration."),
        ]

        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                for pattern in patterns where lower.contains(pattern.needle.lowercased()) {
                    findings.append(
                        makeFinding(
                            severity: pattern.severity,
                            category: .security,
                            origin: .securityAuditor,
                            filePath: file,
                            lineNumber: index + 1,
                            message: pattern.message,
                            suggestedFix: pattern.remediation,
                            confidence: pattern.severity == .critical ? 0.98 : 0.82,
                            evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceTool: ReviewAuditToolName.securitySecrets,
                            blocking: pattern.severity == .critical
                        )
                    )
                }
            }
        }

        let summary = findings.isEmpty
            ? "No hardcoded secrets detected in scoped files."
            : "Detected \(findings.count) potential secret exposure issue(s)."
        return (findings, !scopeFiles.isEmpty, summary)
    }

    static func runSecurityPatternsAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let patterns: [(needle: String, severity: FindingSeverity, message: String, remediation: String, confidence: Double)] = [
            ("eval(", .critical, "Dynamic code evaluation found.", "Remove eval-style execution or strictly sandbox the input.", 0.93),
            ("innerHTML =", .warning, "Direct HTML injection sink found.", "Use safe DOM APIs or sanitize untrusted content before rendering.", 0.78),
            ("shell: true", .critical, "Command execution with shell expansion detected.", "Avoid shell execution or strictly validate/escape all inputs.", 0.90),
            ("http://", .warning, "Insecure cleartext HTTP endpoint found.", "Use HTTPS endpoints unless this is a controlled local-only exception.", 0.74),
            ("NSAllowsArbitraryLoads", .warning, "ATS relaxation detected.", "Scope ATS exceptions narrowly and document the reason.", 0.71),
        ]

        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                for pattern in patterns where line.contains(pattern.needle) {
                    findings.append(
                        makeFinding(
                            severity: pattern.severity,
                            category: .security,
                            origin: .securityAuditor,
                            filePath: file,
                            lineNumber: index + 1,
                            message: pattern.message,
                            suggestedFix: pattern.remediation,
                            confidence: pattern.confidence,
                            evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceTool: ReviewAuditToolName.securityPatterns,
                            blocking: pattern.severity == .critical
                        )
                    )
                }
            }
        }

        let summary = findings.isEmpty
            ? "No insecure security patterns detected in scoped files."
            : "Detected \(findings.count) insecure pattern(s) in scoped files."
        return (findings, !scopeFiles.isEmpty, summary)
    }

    static func runSecurityDependenciesAudit(
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let managers: [(manifest: String, arguments: [String], label: String)] = [
            ("package-lock.json", ["audit", "--json"], "npm"),
            ("pnpm-lock.yaml", ["audit", "--json"], "pnpm"),
            ("yarn.lock", ["audit", "--json"], "yarn"),
        ]

        for manager in managers {
            let manifestURL = workspacePath.appendingPathComponent(manager.manifest)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            guard let result = commandOutput(
                executable: "/usr/bin/env",
                arguments: [manager.label] + manager.arguments,
                currentDirectoryURL: workspacePath
            ) else {
                return ([], false, "Failed to run \(manager.label) dependency audit.")
            }
            return parseDependencyAuditOutput(
                result.output,
                manager: manager.label,
                status: result.status
            )
        }

        return ([], false, "No supported dependency manifest found for security dependency audit.")
    }

    private static func parseDependencyAuditOutput(
        _ output: String,
        manager: String,
        status: Int32
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let lower = output.lowercased()
        let critical = lower.contains("\"critical\":") && !lower.contains("\"critical\":0")
        let high = lower.contains("\"high\":") && !lower.contains("\"high\":0")
        guard critical || high || status != 0 else {
            return ([], true, "No blocking dependency vulnerabilities reported by \(manager) audit.")
        }

        let severity: FindingSeverity = critical ? .critical : .warning
        let finding = makeFinding(
            severity: severity,
            category: .security,
            origin: .securityAuditor,
            filePath: "\(manager)-dependency-audit",
            lineNumber: nil,
            message: "\(manager) audit reported vulnerable dependencies.",
            suggestedFix: "Review the dependency audit report, update or replace vulnerable packages, and re-run the audit.",
            confidence: critical ? 0.92 : 0.80,
            evidence: String(output.prefix(400)),
            sourceTool: ReviewAuditToolName.securityDependencies,
            blocking: critical
        )
        return ([finding], true, "Dependency audit reported vulnerabilities for \(manager).")
    }
}
