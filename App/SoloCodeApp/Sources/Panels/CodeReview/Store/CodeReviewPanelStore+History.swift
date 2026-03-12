import CoderEngine
import Foundation
extension CodeReviewPanelStore {
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
        if let bridged = mergeHistoricalFindingsWithRust(
            primary: primary,
            fallback: fallback
        ) {
            return bridged
        }
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

}
enum ReviewPanelHistoricalFindingsLoader {
    static var fetch: @Sendable (HistoricalFindingsQuery) async -> [HistoricalFindingRecord] = { query in
        HistoricalFindingsQueryService.list(query: query)
    }

    static func list(query: HistoricalFindingsQuery) async -> [HistoricalFindingRecord] {
        await Task.detached(priority: .userInitiated) { await fetch(query) }.value
    }
}
