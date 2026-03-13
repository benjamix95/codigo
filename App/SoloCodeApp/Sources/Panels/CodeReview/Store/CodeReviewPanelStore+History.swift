import CoderEngine
import Foundation
extension CodeReviewPanelStore {
    func fallbackHistoricalFindings() -> [HistoricalFindingRecord] {
        let snapshots = availableSnapshots
        guard !snapshots.isEmpty else { return [] }
        let derived = snapshots
            .compactMap(deriveHistoricalFindingsFromSnapshotWithRust)
            .flatMap { $0 }
        guard !derived.isEmpty else { return [] }
        return shapeHistoricalFindingsWithRust(derived) ?? derived
    }

    var findingsHistoryRefreshKey: String {
        historyAutomaticRefreshKey
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

    func refreshHistoricalFindings() async {
        let refreshKey = findingsHistoryRefreshKey
        guard !isHistoryRefreshInFlight else { return }
        guard let workspaceId = historyWorkspaceId else {
            scheduleHistoricalFindingsSnapshot(
                fallbackHistoricalFindings(),
                error: nil,
                refreshKey: refreshKey
            )
            return
        }
        isHistoryRefreshInFlight = true
        let fallback = fallbackHistoricalFindings()
        scheduleHistoryLoadingState(true, refreshKey: refreshKey)
        defer {
            isHistoryRefreshInFlight = false
            scheduleHistoryLoadingState(false, refreshKey: refreshKey)
        }
        let dbRecords = await ReviewPanelHistoricalFindingsLoader.list(
            query: HistoricalFindingsQuery(workspaceId: workspaceId)
        )
        guard !Task.isCancelled, findingsHistoryRefreshKey == refreshKey else { return }
        scheduleHistoricalFindingsSnapshot(
            mergeHistoricalFindings(primary: dbRecords, fallback: fallback),
            error: nil,
            refreshKey: refreshKey
        )
    }

    var historyWorkspaceId: String? {
        workspaceStore.activeWorkspacePaths.first?.path
            ?? currentSnapshot?.workspacePath
            ?? availableSnapshots.compactMap(\.workspacePath).first
    }

    func severityRank(_ severity: VerifiedFindingSeverity) -> Int {
        switch severity {
        case .critical: return 0
        case .high: return 1
        case .medium: return 2
        case .low: return 3
        case .info: return 4
        }
    }

    private func mergeHistoricalFindings(
        primary: [HistoricalFindingRecord],
        fallback: [HistoricalFindingRecord]
    ) -> [HistoricalFindingRecord] {
        mergeHistoricalFindingsWithRust(
            primary: primary,
            fallback: fallback
        ) ?? primary
    }

    private func mergeHistoricalFindingsWithRust(
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
            snapshot: snapshot
        )
        let response: ReviewCoreReduceHistoryResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_history_records",
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
}
enum ReviewPanelHistoricalFindingsLoader {
    static var fetch: @Sendable (HistoricalFindingsQuery) async -> [HistoricalFindingRecord] = { query in
        HistoricalFindingsQueryService.list(query: query)
    }

    static func list(query: HistoricalFindingsQuery) async -> [HistoricalFindingRecord] {
        await Task.detached(priority: .userInitiated) { await fetch(query) }.value
    }
}

private struct ReviewCoreSnapshotHistoryRequest: Encodable {
    let schemaVersion: Int
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
