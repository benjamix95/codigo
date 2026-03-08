import Foundation

extension CodeReviewAuditService {
    struct ReviewAuditAdapterReport {
        let name: String
        let available: Bool
        let output: String
    }

    static func commandExists(_ name: String) -> Bool {
        guard let result = commandOutput(
            executable: "/usr/bin/env",
            arguments: ["which", name],
            currentDirectoryURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            timeoutSeconds: 4
        ) else {
            return false
        }
        return result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func runOptionalAdapter(
        name: String,
        arguments: [String],
        workspacePath: URL,
        timeoutSeconds: TimeInterval = 10
    ) -> ReviewAuditAdapterReport {
        guard commandExists(name) else {
            return ReviewAuditAdapterReport(name: name, available: false, output: "")
        }
        guard let result = commandOutput(
            executable: "/usr/bin/env",
            arguments: [name] + arguments,
            currentDirectoryURL: workspacePath,
            timeoutSeconds: timeoutSeconds
        ) else {
            return ReviewAuditAdapterReport(name: name, available: false, output: "")
        }
        return ReviewAuditAdapterReport(
            name: name,
            available: true,
            output: result.output
        )
    }

    static func parseAdapterHint(
        _ report: ReviewAuditAdapterReport,
        matchers: [String],
        findingMessage: String,
        filePath: String
    ) -> CodeReviewFinding? {
        guard report.available else { return nil }
        let lower = report.output.lowercased()
        guard matchers.contains(where: { lower.contains($0.lowercased()) }) else {
            return nil
        }
        return makeFinding(
            severity: .warning,
            category: .security,
            origin: .auditTool,
            filePath: filePath,
            lineNumber: nil,
            message: findingMessage,
            suggestedFix: "Verifica il report dell'adapter \(report.name) e applica il remediation suggerito.",
            confidence: 0.74,
            evidence: String(report.output.prefix(280)),
            sourceTool: report.name,
            blocking: false
        )
    }
}
