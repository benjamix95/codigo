import Foundation

extension CodeReviewSessionState {
    public func addCandidate(_ candidate: ReviewCandidate) {
        candidates.append(candidate)
        events.append(.candidateAdded(candidateId: candidate.id, filePath: candidate.filePath))
        notifyChange()
    }

    public func addCandidates(_ newCandidates: [ReviewCandidate]) {
        guard !newCandidates.isEmpty else { return }
        for candidate in newCandidates {
            candidates.append(candidate)
            events.append(.candidateAdded(candidateId: candidate.id, filePath: candidate.filePath))
        }
        notifyChange()
    }

    public func updateCandidateStatus(
        candidateId: String,
        status: ReviewCandidateStatus,
        method: String?,
        report: String?,
        falsePositiveReason: String? = nil
    ) -> Bool {
        guard let index = candidates.firstIndex(where: { $0.id == candidateId }) else {
            return false
        }
        candidates[index].verificationStatus = status
        candidates[index].verificationMethod = method
        candidates[index].verificationReport = report
        candidates[index].falsePositiveReason = falsePositiveReason
        candidates[index].verifiedAt = status == .verified ? Date() : nil
        switch status {
        case .verified:
            events.append(.candidateVerified(candidateId: candidateId))
        case .rejectedFalsePositive:
            events.append(.candidateRejected(candidateId: candidateId, reason: falsePositiveReason ?? "false_positive"))
        default:
            break
        }
        notifyChange()
        return true
    }

    public func promoteCandidateToFinding(candidateId: String) -> Bool {
        guard let candidate = candidates.first(where: { $0.id == candidateId }),
              candidate.verificationStatus == .verified
        else {
            return false
        }
        guard !findings.contains(where: { $0.id == candidateId }) else {
            return true
        }
        findings.append(.fromCandidate(candidate))
        events.append(.findingAdded(
            findingId: candidate.id,
            severity: candidate.severity.rawValue,
            filePath: candidate.filePath
        ))
        notifyChange()
        return true
    }

    public func upsertPatch(_ patch: ReviewPatchArtifact) {
        if let index = patches.firstIndex(where: { $0.id == patch.id || $0.findingId == patch.findingId }) {
            patches[index] = patch
        } else {
            patches.append(patch)
        }

        if let findingIndex = findings.firstIndex(where: { $0.id == patch.findingId }) {
            findings[findingIndex].patchArtifactId = patch.id
            findings[findingIndex].status = switch patch.status {
            case .draft: .patchPreparing
            case .verified: .patchReady
            case .applied: .patchApplied
            case .applyFailed: .patchFailed
            case .prOpened: .prOpened
            case .merged: .merged
            case .conflict: .blocked
            case .rolledBack: .blocked
            }
        }

        switch patch.status {
        case .draft:
            events.append(.patchPrepared(patchId: patch.id, findingId: patch.findingId))
        case .verified:
            events.append(CodeReviewSessionEvent(
                type: .patchVerified,
                detail: "Patch \(patch.id) verified",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .applyFailed:
            events.append(CodeReviewSessionEvent(
                type: .patchApplyFailed,
                detail: patch.applyMessage ?? "Patch apply failed",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .prOpened:
            events.append(CodeReviewSessionEvent(
                type: .prOpened,
                detail: patch.prURL ?? "Pull request opened",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .merged:
            events.append(CodeReviewSessionEvent(
                type: .prMerged,
                detail: patch.prURL ?? "Patch merged",
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .conflict:
            events.append(CodeReviewSessionEvent(
                type: .conflictDetected,
                detail: patch.conflicts.joined(separator: ", "),
                metadata: ["patch_id": patch.id, "finding_id": patch.findingId]
            ))
        case .applied, .rolledBack:
            events.append(.findingFixApplied(findingId: patch.findingId))
        }

        outcome = snapshot().buildOutcomeSummary()
        notifyChange()
    }

    public func patch(forFindingId findingId: String) -> ReviewPatchArtifact? {
        patches.first(where: { $0.findingId == findingId })
    }
}

extension CodeReviewSessionSnapshot {
    public func buildOutcomeSummary(summaryOverride: String? = nil) -> ReviewSessionOutcome {
        let verifiedFindings = findings.count
        let falsePositives = candidates.filter { $0.verificationStatus == .rejectedFalsePositive }.count
        let patchesReady = patches.filter { $0.status == .verified || $0.status == .draft }.count
        let patchesApplied = patches.filter { $0.status == .applied }.count
        let prsOpened = patches.filter { $0.prStatus == .opened || $0.status == .prOpened }.count
        let mergedPatches = patches.filter { $0.mergeStatus == .merged || $0.status == .merged }.count
        let conflictsDetected = patches.reduce(0) { $0 + $1.conflicts.count }
        let manualActionRequired = patches.contains {
            $0.status == .conflict || $0.mergeStatus == .blocked || $0.status == .applyFailed
        } || candidates.contains { $0.verificationStatus == .inconclusive }
        let summary = summaryOverride
            ?? "\(verifiedFindings) verified finding(s), \(falsePositives) false positive(s), \(patchesApplied) patch(es) applied."
        return ReviewSessionOutcome(
            summary: summary,
            verifiedFindings: verifiedFindings,
            falsePositives: falsePositives,
            patchesReady: patchesReady,
            patchesApplied: patchesApplied,
            prsOpened: prsOpened,
            mergedPatches: mergedPatches,
            conflictsDetected: conflictsDetected,
            manualActionRequired: manualActionRequired,
            testsStatus: lastTestStatus
        )
    }
}
