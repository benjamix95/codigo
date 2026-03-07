import CoderEngine
import Foundation

enum CodeReviewPromptBuilder {
    static func targetedFixPrompt(
        snapshot: CodeReviewSessionSnapshot,
        findings: [CodeReviewFinding],
        targetSessionId: String? = nil
    ) -> String {
        let files = Array(Set(findings.map(\.filePath))).sorted()
        let findingsList = findings.map { finding in
            let line = finding.lineNumber.map { ":\($0)" } ?? ""
            let suggestedFix = finding.suggestedFix.map { "\n  Suggested fix: \($0)" } ?? ""
            return "- \(finding.filePath)\(line) [\(finding.severity.rawValue)] \(finding.message)\(suggestedFix)"
        }.joined(separator: "\n")

        return """
        \(scopePrefix(for: snapshot)) Apply targeted fixes for the selected code review findings\(sessionClause(for: targetSessionId)).
        Files in scope:
        \(files.joined(separator: "\n"))

        Findings to fix:
        \(findingsList)

        Requirements:
        - fix only the listed findings,
        - keep changes minimal and localized,
        - run relevant verification after changes,
        - report what was fixed and any residual risks.
        """
    }

    private static func scopePrefix(for snapshot: CodeReviewSessionSnapshot) -> String {
        switch snapshot.scope?.type {
        case .staged:
            return "[REVIEW_SCOPE:staged]"
        case .againstRef:
            return "[AGAINST:\(snapshot.scope?.ref ?? "HEAD~1")]"
        case .uncommitted, .none:
            return "[REVIEW_SCOPE:uncommitted]"
        }
    }

    private static func sessionClause(for sessionId: String?) -> String {
        guard let sessionId, !sessionId.isEmpty else { return "" }
        return " in session \(sessionId)"
    }
}
