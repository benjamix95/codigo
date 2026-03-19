import Foundation

extension CodeReviewSessionState {
    public func addFinding(_ finding: CodeReviewFinding) {
        _ = applySessionAction(operation: "add_finding") {
            $0.finding = finding
        }
    }

    public func addFindings(_ newFindings: [CodeReviewFinding]) {
        guard !newFindings.isEmpty else { return }
        _ = applySessionAction(operation: "add_findings") {
            $0.findings = newFindings
        }
    }

    public func replaceOpenFindings(
        in reviewedFiles: Set<String>,
        with newFindings: [CodeReviewFinding]
    ) {
        _ = applySessionAction(operation: "replace_open_findings") {
            $0.files = Array(reviewedFiles)
            $0.findings = newFindings
        }
    }

    public func replaceOpenFindings(with newFindings: [CodeReviewFinding]) {
        replaceOpenFindings(
            in: Set(newFindings.map(\.filePath)),
            with: newFindings
        )
    }

    public func applyFix(findingId: String) -> Bool {
        applySessionAction(operation: "apply_fix") {
            $0.findingId = findingId
        }
    }

    public func dismissFinding(
        findingId: String,
        reason: String = "dismissed"
    ) -> Bool {
        applySessionAction(operation: "dismiss") {
            $0.findingId = findingId
            $0.reason = reason
        }
    }

    public func addComment(
        findingId: String,
        comment: FindingComment
    ) -> Bool {
        applySessionAction(operation: "comment") {
            $0.findingId = findingId
            $0.comment = comment
        }
    }

    public func closeFinding(
        findingId: String,
        reason: String = "closed"
    ) -> Bool {
        applySessionAction(operation: "close_finding") {
            $0.findingId = findingId
            $0.reason = reason
        }
    }

    public func finding(byId id: String) -> CodeReviewFinding? {
        findings.first { $0.id == id }
    }

    public func updateConfig(_ newConfig: SessionConfig) {
        _ = applySessionAction(operation: "configure") {
            $0.config = newConfig
        }
    }

    public func markAllOpenFindingsAsFixApplied() {
        _ = applySessionAction(operation: "mark_all_open_findings_as_fix_applied")
    }

    public func markOpenFindingsAsFixApplied(in files: Set<String>) {
        guard !files.isEmpty else { return }
        _ = applySessionAction(operation: "mark_open_findings_as_fix_applied") {
            $0.files = Array(files)
        }
    }
}
