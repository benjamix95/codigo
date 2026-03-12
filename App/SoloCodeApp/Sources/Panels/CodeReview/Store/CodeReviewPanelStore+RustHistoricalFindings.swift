import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func fallbackHistoricalFindings() -> [HistoricalFindingRecord] {
        let snapshots = availableSnapshots
        guard !snapshots.isEmpty else { return [] }

        let derived = snapshots.flatMap { snapshot in
            deriveHistoricalFindingsFromSnapshotWithRust(snapshot) ?? []
        }
        if let shaped = shapeHistoricalFindingsWithRust(derived), !shaped.isEmpty {
            return shaped
        }
        return legacyFallbackHistoricalFindings(from: snapshots)
    }

    func mergeHistoricalFindingsWithRust(
        primary: [HistoricalFindingRecord],
        fallback: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord]? {
        let request = ReviewCoreReduceHistoryRequest(
            schemaVersion: 1,
            operation: "merge_history",
            primary: primary,
            fallback: fallback
        )
        let response: ReviewCoreReduceHistoryResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: request
        )
        return response?.mergedHistory
    }

    private func deriveHistoricalFindingsFromSnapshotWithRust(
        _ snapshot: CodeReviewSessionSnapshot
    ) -> [HistoricalFindingRecord]? {
        let request = ReviewCoreSnapshotHistoryRequest(
            schemaVersion: 1,
            operation: "derive_history_records_from_snapshot",
            snapshot: snapshot
        )
        let response: ReviewCoreReduceHistoryResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: request
        )
        return response?.mergedHistory
    }

    private func shapeHistoricalFindingsWithRust(
        _ records: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord]? {
        let request = ReviewCoreHistoricalShapeRequest(
            schemaVersion: 1,
            records: records
        )
        let response: ReviewCoreReduceHistoryResponse? = ReviewCoreBridge.call(
            functionName: "review_core_shape_historical_findings",
            request: request
        )
        return response?.mergedHistory
    }

    private func legacyFallbackHistoricalFindings(
        from snapshots: [CodeReviewSessionSnapshot]
    ) -> [HistoricalFindingRecord] {
        var recordsById: [String: HistoricalFindingRecord] = [:]
        for snapshot in snapshots {
            let eventsByFindingId = Dictionary(grouping: snapshot.events) { event in
                event.metadata["finding_id"] ?? event.metadata["candidate_id"] ?? ""
            }
            for finding in snapshot.findings {
                let patch = snapshot.patches.first(where: { $0.findingId == finding.id })
                let domain: VerifiedFindingDomain =
                    finding.origin == .securityAuditor || finding.category == .security ? .security : .bug
                let candidateTimeline = (eventsByFindingId[finding.id] ?? []).map { event in
                    HistoricalFindingTimelineItem(
                        eventId: event.id,
                        eventType: event.type.rawValue,
                        detail: event.detail,
                        createdAt: event.timestamp,
                        metadata: event.metadata
                    )
                }
                let status = legacyHistoricalStatus(for: finding, patch: patch)
                let record = HistoricalFindingRecord(
                    findingId: finding.id,
                    sessionId: snapshot.sessionId,
                    workspaceId: snapshot.workspacePath ?? historyWorkspaceId ?? "workspace",
                    domain: domain,
                    severity: legacyHistoricalSeverity(from: finding.severity),
                    title: finding.message,
                    summary: finding.evidence ?? finding.message,
                    status: status,
                    filePath: finding.filePath,
                    lineStart: finding.lineNumber,
                    sourceOrigin: finding.origin.rawValue,
                    closedReason: legacyHistoricalClosedReason(for: finding.status),
                    patchId: patch?.id,
                    patchApplyStatus: patch.map { legacyHistoricalPatchApplyStatus(from: $0) },
                    revalidationReportId: patch?.validationRunId,
                    revalidationVerdict: legacyHistoricalRevalidationVerdict(for: patch),
                    createdAt: finding.createdAt,
                    updatedAt: patch?.updatedAt ?? finding.verifiedAt ?? finding.createdAt,
                    resolvedAt: finding.status.isAppliedState ? (patch?.updatedAt ?? finding.verifiedAt) : nil,
                    resumeEligible: !status.isTerminalHistoryStatus,
                    timeline: candidateTimeline
                )
                if let existing = recordsById[record.id], existing.updatedAt > record.updatedAt { continue }
                recordsById[record.id] = record
            }
        }
        return recordsById.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func legacyHistoricalSeverity(from severity: FindingSeverity) -> VerifiedFindingSeverity {
        switch severity {
        case .critical: return .critical
        case .warning: return .medium
        case .suggestion: return .low
        case .info: return .info
        }
    }

    private func legacyHistoricalStatus(
        for finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?
    ) -> VerifiedFindingStatus {
        if let patch {
            if patch.status == .applied {
                switch patch.validationStatus {
                case .passed: return .fixedVerified
                case .failed: return .fixFailed
                case .pending: return .patchApplied
                }
            }
            if patch.status == .rolledBack { return .rollbackApplied }
        }
        switch finding.status {
        case .open: return .verified
        case .fixApplied, .patchApplied: return .patchApplied
        case .patchPreparing: return .patchPreparing
        case .patchReady: return .patchPrepared
        case .patchApplying: return .patchReviewed
        case .patchFailed: return .fixFailed
        case .prOpened, .merged, .closed: return .closed
        case .blocked: return .needsManualReview
        case .dismissed, .wontFix: return .rejected
        }
    }

    private func legacyHistoricalPatchApplyStatus(
        from patch: ReviewPatchArtifact
    ) -> VerifiedPatchApplyStatus {
        switch patch.status {
        case .draft, .verified, .prOpened, .merged, .conflict: return .notApplied
        case .applied: return .applied
        case .applyFailed: return .failed
        case .rolledBack: return .rolledBack
        }
    }

    private func legacyHistoricalRevalidationVerdict(
        for patch: ReviewPatchArtifact?
    ) -> RevalidationVerdict? {
        guard let patch, patch.status == .applied || patch.status == .applyFailed else { return nil }
        switch patch.validationStatus {
        case .passed: return .fixedVerified
        case .failed: return .fixFailed
        case .pending: return nil
        }
    }

    private func legacyHistoricalClosedReason(for status: FindingStatus) -> String? {
        switch status {
        case .dismissed: return "dismissed"
        case .wontFix: return "wont_fix"
        case .merged: return "merged"
        case .prOpened: return "pr_opened"
        case .closed: return "closed"
        default: return nil
        }
    }
}

private struct ReviewCoreSnapshotHistoryRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
}

private struct ReviewCoreHistoricalShapeRequest: Encodable {
    let schemaVersion: Int
    let records: [HistoricalFindingRecord]
}

private struct ReviewCoreReduceHistoryResponse: Decodable {
    let mergedHistory: [HistoricalFindingRecord]
}

private struct ReviewCoreReduceHistoryRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let primary: [HistoricalFindingRecord]
    let fallback: [HistoricalFindingRecord]
}

private extension VerifiedFindingStatus {
    var isTerminalHistoryStatus: Bool {
        switch self {
        case .fixedVerified, .closed, .rejected: return true
        case .candidate, .verifying, .verified, .needsManualReview, .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixFailed, .rollbackApplied: return false
        }
    }
}
