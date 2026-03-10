import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    var findingsHistoryRefreshKey: String {
        let workspaceKey = historyWorkspaceId ?? "no-workspace"
        let sessionKey = selectedSessionId ?? "no-session"
        let snapshotKey = currentSnapshot?.lastUpdatedAt.timeIntervalSince1970.description ?? "0"
        return [workspaceKey, sessionKey, snapshotKey].joined(separator: "|")
    }

    var selectedHistoricalFinding: HistoricalFindingRecord? {
        historyRecords.first(where: { $0.id == selectedHistoricalFindingId })
    }

    var filteredHistoricalFindings: [HistoricalFindingRecord] {
        historyRecords.filter { record in
            record.matches(statusFilter: historyStatusFilter)
                && record.matches(domainFilter: historyDomainFilter)
                && record.matches(severityFilter: historySeverityFilter)
        }
    }

    var historicalResumeQueue: [HistoricalFindingRecord] {
        historyRecords
            .filter(\.resumeEligible)
            .filter { record in
                record.matches(domainFilter: historyDomainFilter)
                    && record.matches(severityFilter: historySeverityFilter)
            }
            .sorted { lhs, rhs in
                if lhs.severity == rhs.severity {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return severityRank(lhs.severity) < severityRank(rhs.severity)
            }
    }

    var historicalArchiveRecords: [HistoricalFindingRecord] {
        filteredHistoricalFindings
            .filter { historyStatusFilter == .resumeQueue ? false : !($0.resumeEligible && historyStatusFilter == .all) }
    }

    func refreshHistoricalFindings() async {
        guard let workspaceId = historyWorkspaceId else {
            historyRecords = fallbackHistoricalFindings()
            return
        }
        isHistoryLoading = true
        defer { isHistoryLoading = false }

        let dbRecords = HistoricalFindingsQueryService.list(
            query: HistoricalFindingsQuery(workspaceId: workspaceId)
        )
        let fallback = fallbackHistoricalFindings()
        historyRecords = mergeHistoricalFindings(primary: dbRecords, fallback: fallback)
        historyLoadError = nil
    }

    func selectHistoricalFinding(_ findingId: String) {
        guard historyRecords.contains(where: { $0.id == findingId }) else { return }
        selectedFindingId = nil
        selectedHistoricalFindingId = findingId
        selectTab(.history)
    }

    func resumeHistoricalFinding(_ record: HistoricalFindingRecord) async {
        if currentPublishedFindings.contains(where: { $0.id == record.findingId }) {
            focusFinding(record.findingId)
            return
        }

        selectedHistoricalFindingId = nil
        await startReview(
            scope: .workspace,
            modes: selectedModes,
            promptOverride: historicalResumePrompt(for: record),
            invocationLabel: "Resume \(record.findingId)"
        )
    }

    func historicalResumePrompt(for record: HistoricalFindingRecord) -> String {
        """
        [REVIEW_SCOPE:workspace] [MODE:standard] [MODE:bug-finder] [MODE:security-audit]
        Resume the unresolved historical finding \(record.findingId).
        File: \(record.filePath)\(record.lineStart.map { ":\($0)" } ?? "")
        Domain: \(record.domain.rawValue)
        Source origin: \(record.sourceLabel)
        Current status: \(record.status.rawValue)
        Summary: \(record.title)
        Evidence summary: \(record.summary)
        Last patch status: \(record.patchApplyStatus?.rawValue ?? "none")
        Last revalidation verdict: \(record.revalidationVerdict?.rawValue ?? "none")
        Continue from the existing finding history. Preserve traceability and propose the next minimal safe fix.
        """
    }

    private var historyWorkspaceId: String? {
        workspaceStore.activeWorkspacePaths.first?.path
            ?? currentSnapshot?.workspacePath
            ?? availableSnapshots.compactMap(\.workspacePath).first
    }

    private func mergeHistoricalFindings(
        primary: [HistoricalFindingRecord],
        fallback: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord] {
        var merged = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for record in fallback where merged[record.id] == nil {
            merged[record.id] = record
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.resumeEligible != rhs.resumeEligible {
                return lhs.resumeEligible && !rhs.resumeEligible
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func fallbackHistoricalFindings() -> [HistoricalFindingRecord] {
        let snapshots = availableSnapshots
        guard !snapshots.isEmpty else { return [] }

        var recordsById: [String: HistoricalFindingRecord] = [:]
        for snapshot in snapshots {
            let eventsByFindingId = Dictionary(grouping: snapshot.events) { event in
                event.metadata["finding_id"] ?? event.metadata["candidate_id"] ?? ""
            }
            for finding in snapshot.findings {
                let patch = snapshot.patches.first(where: { $0.findingId == finding.id })
                let domain: VerifiedFindingDomain =
                    finding.origin == .securityAuditor || finding.category == .security
                    ? .security
                    : .bug
                let candidateTimeline = (eventsByFindingId[finding.id] ?? []).map { event in
                    HistoricalFindingTimelineItem(
                        eventId: event.id,
                        eventType: event.type.rawValue,
                        detail: event.detail,
                        createdAt: event.timestamp,
                        metadata: event.metadata
                    )
                }
                let record = HistoricalFindingRecord(
                    findingId: finding.id,
                    sessionId: snapshot.sessionId,
                    workspaceId: snapshot.workspacePath ?? historyWorkspaceId ?? "workspace",
                    domain: domain,
                    severity: historicalSeverity(from: finding.severity),
                    title: finding.message,
                    summary: finding.evidence ?? finding.message,
                    status: historicalStatus(for: finding, patch: patch),
                    filePath: finding.filePath,
                    lineStart: finding.lineNumber,
                    sourceOrigin: finding.origin.rawValue,
                    closedReason: historicalClosedReason(for: finding.status),
                    patchId: patch?.id,
                    patchApplyStatus: patch.map { historicalPatchApplyStatus(from: $0) },
                    revalidationReportId: patch?.validationRunId,
                    revalidationVerdict: historicalRevalidationVerdict(for: patch),
                    createdAt: finding.createdAt,
                    updatedAt: patch?.updatedAt ?? finding.verifiedAt ?? finding.createdAt,
                    resolvedAt: finding.status.isAppliedState ? (patch?.updatedAt ?? finding.verifiedAt) : nil,
                    resumeEligible: !historicalStatus(for: finding, patch: patch).isTerminalHistoryStatus,
                    timeline: candidateTimeline
                )
                if let existing = recordsById[record.id], existing.updatedAt > record.updatedAt {
                    continue
                }
                recordsById[record.id] = record
            }
        }
        return recordsById.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func severityRank(_ severity: VerifiedFindingSeverity) -> Int {
        switch severity {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }

    private func historicalSeverity(from severity: FindingSeverity) -> VerifiedFindingSeverity {
        switch severity {
        case .critical: return .critical
        case .warning: return .medium
        case .suggestion: return .low
        case .info: return .info
        }
    }

    private func historicalStatus(
        for finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?
    ) -> VerifiedFindingStatus {
        if let patch {
            if patch.status == .applied {
                switch patch.validationStatus {
                case .passed:
                    return .fixedVerified
                case .failed:
                    return .fixFailed
                case .pending:
                    return .patchApplied
                }
            }
            if patch.status == .rolledBack {
                return .rollbackApplied
            }
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

    private func historicalPatchApplyStatus(
        from patch: ReviewPatchArtifact
    ) -> VerifiedPatchApplyStatus {
        switch patch.status {
        case .draft, .verified, .prOpened, .merged, .conflict:
            return .notApplied
        case .applied:
            return .applied
        case .applyFailed:
            return .failed
        case .rolledBack:
            return .rolledBack
        }
    }

    private func historicalRevalidationVerdict(
        for patch: ReviewPatchArtifact?
    ) -> RevalidationVerdict? {
        guard let patch, patch.status == .applied || patch.status == .applyFailed else { return nil }
        switch patch.validationStatus {
        case .passed:
            return .fixedVerified
        case .failed:
            return .fixFailed
        case .pending:
            return nil
        }
    }

    private func historicalClosedReason(
        for status: FindingStatus
    ) -> String? {
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

private extension VerifiedFindingStatus {
    var isTerminalHistoryStatus: Bool {
        switch self {
        case .fixedVerified, .closed, .rejected:
            return true
        case .candidate, .verifying, .verified, .needsManualReview, .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixFailed, .rollbackApplied:
            return false
        }
    }
}
