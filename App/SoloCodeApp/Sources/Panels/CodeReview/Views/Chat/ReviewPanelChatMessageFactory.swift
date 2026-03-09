import CoderEngine
import Foundation

enum ReviewPanelChatMessageFactory {
    static func commandInvocation(
        title: String,
        detail: String?
    ) -> ReviewPanelMessage {
        let content = detail.map { "\(title)\n\n\($0)" } ?? title
        let lines = normalizedLines(from: content)
        return ReviewPanelMessage(
            role: .user,
            kind: .commandInvocation,
            content: content,
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "command",
                        title: "Command",
                        lines: lines,
                        style: .prose,
                        isInitiallyExpanded: true
                    )
                ]
            )
        )
    }

    static func findingUpdate(
        text: String
    ) -> ReviewPanelMessage {
        ReviewPanelMessage(
            role: .system,
            kind: .findingMutation,
            content: text,
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "finding-update",
                        title: "Finding Update",
                        lines: [text],
                        style: .prose,
                        isInitiallyExpanded: true
                    )
                ]
            )
        )
    }

    static func findingUpdate(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        title: String,
        detail: String? = nil
    ) -> ReviewPanelMessage {
        VerifiedFindingsChatPresentationService.reviewPanelMessage(
            snapshot: snapshot,
            findingId: findingId,
            eventTitle: title,
            eventDetail: detail
        ) ?? findingUpdate(
            text: detail.map { "\(title)\n\n\($0)" } ?? title
        )
    }

    static func summary(snapshot: CodeReviewSessionSnapshot) -> ReviewPanelMessage {
        let content = summaryText(from: snapshot)
        return ReviewPanelMessage(
            role: .system,
            kind: .summary,
            content: content,
            presentation: ReviewPanelMessagePresentation(
                sections: ReviewPanelChatStructuredContent.sections(
                    for: ReviewPanelMessage(
                        role: .system,
                        kind: .summary,
                        content: content
                    )
                )
            )
        )
    }

    static func finalizeReviewRunMessage(_ message: inout ReviewPanelMessage) {
        guard message.kind == .reviewRun else { return }
        let sections = ReviewPanelChatStructuredContent.sections(for: message)
        guard !sections.isEmpty else { return }
        message.presentation = ReviewPanelMessagePresentation(sections: sections)
    }

    private static func summaryText(from snapshot: CodeReviewSessionSnapshot) -> String {
        let projection = snapshot.verifiedFindingsProjection
        let securityGate = snapshot.verifiedFindings.map(VerifiedFindingsSecurityGateService.evaluate)
        let header = """
        ## Code Review Summary
        - session_id: \(snapshot.sessionId)
        - phase: \(snapshot.phase.rawValue)
        - stage: \(snapshot.stage.rawValue)
        - scope: \(snapshot.scope?.description ?? "unknown")
        - verified_findings: \(snapshot.findings.count)
        - candidates: \(snapshot.candidates.count)
        - patches: \(snapshot.patches.count)
        - verified_queue: \(projection.verifiedQueue.count)
        - candidate_queue: \(projection.candidateQueue.count)
        - duplicate_findings: \(projection.duplicatesCount)
        - stale_candidates: \(projection.staleCandidatesCount)
        - security_gate_ready: \(securityGate?.ready == true ? "true" : "false")
        - outcome: \(snapshot.outcome.summary)
        """

        let findings = snapshot.findings.map { finding in
            let line = finding.lineNumber.map { ":\($0)" } ?? ""
            return "- [\(finding.severity.rawValue)] \(finding.filePath)\(line) — \(finding.message)"
        }

        let securityLines: [String] = securityGate.map { ["", "## Security Gate", "- \($0.summary)"] } ?? []
        return ([header] + securityLines + findings).joined(separator: "\n")
    }

    private static func normalizedLines(from content: String) -> [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
