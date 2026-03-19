import Foundation

extension CodeReviewSessionState {
    public func addFinding(_ finding: CodeReviewFinding) {
        findings.append(finding)
        events.append(.findingAdded(
            findingId: finding.id,
            severity: finding.severity.rawValue,
            filePath: finding.filePath
        ))
        notifyChange()
    }

    public func addFindings(_ newFindings: [CodeReviewFinding]) {
        guard !newFindings.isEmpty else { return }
        for finding in newFindings {
            findings.append(finding)
            events.append(.findingAdded(
                findingId: finding.id,
                severity: finding.severity.rawValue,
                filePath: finding.filePath
            ))
        }
        notifyChange()
    }

    public func replaceOpenFindings(
        in reviewedFiles: Set<String>,
        with newFindings: [CodeReviewFinding]
    ) {
        findings.removeAll {
            $0.status.isOpenState
                && reviewedFiles.contains($0.filePath)
        }
        for finding in newFindings {
            findings.append(finding)
            events.append(.findingAdded(
                findingId: finding.id,
                severity: finding.severity.rawValue,
                filePath: finding.filePath
            ))
        }
        notifyChange()
    }

    public func replaceOpenFindings(with newFindings: [CodeReviewFinding]) {
        replaceOpenFindings(
            in: Set(newFindings.map(\.filePath)),
            with: newFindings
        )
    }

    public func applyFix(findingId: String) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].status = findings[idx].patchArtifactId == nil ? .fixApplied : .patchApplied
        events.append(.findingFixApplied(findingId: findingId))
        notifyChange()
        return true
    }

    public func dismissFinding(
        findingId: String,
        reason: String = "dismissed"
    ) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].status = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == FindingStatus.wontFix.rawValue
            ? .wontFix
            : .dismissed
        events.append(.findingDismissed(findingId: findingId, reason: reason))
        notifyChange()
        return true
    }

    public func addComment(
        findingId: String,
        comment: FindingComment
    ) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].comments.append(comment)
        events.append(CodeReviewSessionEvent(
            type: .findingCommented,
            detail: "Comment added to \(findingId)",
            metadata: [
                "finding_id": findingId,
                "comment_id": comment.id,
            ]
        ))
        notifyChange()
        return true
    }

    public func closeFinding(
        findingId: String,
        reason: String = "closed"
    ) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        let currentStatus = findings[idx].status
        let canClose: Bool
        switch currentStatus {
        case .merged, .dismissed, .wontFix, .closed:
            canClose = true
        case .patchApplied, .fixApplied:
            if let patchId = findings[idx].patchArtifactId,
               let patch = patches.first(where: { $0.id == patchId }) {
                canClose = patch.validationStatus == .passed
            } else {
                canClose = false
            }
        default:
            canClose = false
        }
        guard canClose else { return false }
        findings[idx].status = .closed
        events.append(CodeReviewSessionEvent(
            type: .outcomePublished,
            detail: "Finding \(findingId) closed",
            metadata: ["finding_id": findingId, "reason": reason]
        ))
        notifyChange()
        return true
    }

    public func finding(byId id: String) -> CodeReviewFinding? {
        findings.first { $0.id == id }
    }

    public func updateConfig(_ newConfig: SessionConfig) {
        config = newConfig
        events.append(CodeReviewSessionEvent(
            type: .configUpdated,
            detail: "Config updated"
        ))
        notifyChange()
    }

    public func markAllOpenFindingsAsFixApplied() {
        var changedFindingIDs: [String] = []
        for index in findings.indices where findings[index].status.isOpenState {
            findings[index].status = .fixApplied
            changedFindingIDs.append(findings[index].id)
        }
        for findingId in changedFindingIDs {
            events.append(.findingFixApplied(findingId: findingId))
        }
        if !changedFindingIDs.isEmpty {
            notifyChange()
        }
    }

    public func markOpenFindingsAsFixApplied(in files: Set<String>) {
        guard !files.isEmpty else { return }
        var changedFindingIDs: [String] = []
        for index in findings.indices
        where findings[index].status.isOpenState && files.contains(findings[index].filePath) {
            findings[index].status = .patchApplied
            changedFindingIDs.append(findings[index].id)
        }
        for findingId in changedFindingIDs {
            events.append(.findingFixApplied(findingId: findingId))
        }
        if !changedFindingIDs.isEmpty {
            notifyChange()
        }
    }
}
