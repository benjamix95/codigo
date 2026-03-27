import CoderEngine
import Foundation
extension CodeReviewPanelStore {
    var historyLiveRefreshKey: String {
        let sessionKey = selectedSessionId ?? "no-session"
        let snapshotKey = currentSnapshot.map {
            "\($0.mutationSequence)|\($0.lastUpdatedAt.timeIntervalSince1970)|\($0.phase.rawValue)|\($0.activeWorkerCount)"
        } ?? "0"
        let workerKey = currentHistoryLiveWorkerPlans
            .map { "\($0.workerId):\($0.fileCount):\($0.files.joined(separator: ","))" }
            .joined(separator: "|")
        let cardKey = currentHistoryLiveCards
            .map { "\($0.swarmId):\($0.status):\($0.currentStepTitle)" }
            .joined(separator: "|")
        return [findingsHistoryRefreshKey, sessionKey, snapshotKey, workerKey, cardKey].joined(separator: "|")
    }

    var currentHistoricalLiveRunState: ReviewHistoricalLiveBoardState? {
        guard let snapshot = currentSnapshot else { return nil }
        let pipeline = currentPipelineJobState
            ?? ReviewPipelineJobStateBuilder.build(snapshot: snapshot)
        let workerPlans = currentHistoryLiveWorkerPlans
        let liveCards = currentHistoryLiveCards
        let hasArtifacts = snapshot.isActive
            || snapshot.phase == .completed
            || snapshot.phase == .failed
            || !snapshot.fileLedger.isEmpty
            || !workerPlans.isEmpty
            || !liveCards.isEmpty
        guard hasArtifacts else { return nil }
        let base: ReviewHistoricalLiveBoardState?
        if let rustBoard = ReviewPanelHistoryLiveRustAdapter
            .derive(snapshot: snapshot, workerPlans: workerPlans, liveCards: liveCards)?
            .makeBoardState(pipeline: pipeline) {
            base = rustBoard
        } else {
            base = ReviewPanelHistoryLiveSwiftFallback.derive(
                snapshot: snapshot,
                workerPlans: workerPlans,
                liveCards: liveCards,
                pipeline: pipeline
            )
        }
        guard let board = base else { return nil }
        let running = board.isRunning
        let title = ReviewPanelLiveBoardPresentation.boardHeaderTitle(
            isRunning: running,
            modes: selectedModes,
            scope: snapshot.scope
        )
        let subtitle = ReviewPanelLiveBoardPresentation.boardSubtitle(
            isRunning: running,
            modes: selectedModes
        )
        let headerPipeline = board.pipeline.replacingTitle(
            ReviewPanelLiveBoardPresentation.pipelineCardTitle(
                modes: selectedModes,
                scanDepth: reviewScanDepth
            )
        )
        return ReviewHistoricalLiveBoardState(
            title: title,
            subtitle: subtitle,
            pipeline: headerPipeline,
            workers: board.workers,
            files: board.files,
            isRunning: running
        )
    }

    func fallbackHistoricalFindings() -> [HistoricalFindingRecord] {
        let refreshKey = findingsHistoryRefreshKey
        if let cached = cachedHistoricalFallbacksByRefreshKey[refreshKey] {
            return cached
        }
        let snapshots = availableSnapshots
        guard !snapshots.isEmpty else { return [] }
        let derived = snapshots
            .compactMap { snapshot -> [HistoricalFindingRecord]? in
                ReviewPanelHistorySwiftFallback.deriveHistoricalFindings(from: snapshot)
                    ?? deriveHistoricalFindingsFromSnapshotWithRust(snapshot)
            }
            .flatMap { $0 }
        guard !derived.isEmpty else { return [] }
        let shaped = ReviewPanelHistoricalFindingsLocalReducer.shape(derived)
        cachedHistoricalFallbacksByRefreshKey[refreshKey] = shaped
        if cachedHistoricalFallbacksByRefreshKey.count > 12 {
            cachedHistoricalFallbacksByRefreshKey.removeValue(
                forKey: cachedHistoricalFallbacksByRefreshKey.keys.sorted().first ?? refreshKey
            )
        }
        return shaped
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
        if !applyPanelIntent("focus_historical_finding", value: findingId),
           !ReviewCoreBridge.isEnabled {
            selectedFindingId = nil
            selectedHistoricalFindingId = findingId
        }
        selectTab(.history)
    }

    func resumeHistoricalFinding(_ record: HistoricalFindingRecord) async {
        if currentPublishedFindings.contains(where: { $0.id == record.findingId }) {
            focusFinding(record.findingId)
            return
        }
        clearSelectedHistoricalFinding()
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
        ReviewPanelHistoricalFindingsLocalReducer.merge(
            primary: primary,
            fallback: fallback
        )
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

    private var currentHistoryLiveWorkerPlans: [ReviewPanelHistoryWorkerPlanInput] {
        let reviewActivities = scopedReviewActivitiesForSession(
            taskActivityStore.activities + taskActivityStore.pendingActivities,
            sessionId: selectedSessionId
        )
        return sortedReviewWorkerPlanActivitiesForDisplay(
            selectReviewWorkerActivities(from: reviewActivities)
        ).compactMap { activity in
            guard let workerId = activity.payload["worker_id"],
                  let description = activity.payload["description"],
                  let severity = activity.payload["severity"],
                  let fileCountRaw = activity.payload["fileCount"] else { return nil }
            let files = (activity.payload["files_raw"] ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ReviewPanelHistoryWorkerPlanInput(
                workerId: workerId,
                description: description,
                severity: severity.lowercased(),
                files: files,
                fileCount: Int(fileCountRaw) ?? files.count
            )
        }
    }

    private var currentHistoryLiveCards: [ReviewPanelHistoryLiveCardInput] {
        let sessionId = selectedSessionId
        return taskActivityStore
            .swarmCardStatesIncludingPending(for: conversationId)
            .filter { isCodeReviewSwarmCard($0) && reviewCardBelongsToSession($0, sessionId: sessionId) }
            .map { card in
                ReviewPanelHistoryLiveCardInput(
                    swarmId: card.swarmId,
                    displayName: card.displayName,
                    status: card.status.rawValue,
                    currentStepTitle: card.currentStepTitle,
                    warningCount: card.warningCount,
                    files: historyLiveFiles(from: card),
                    workerId: historyLiveWorkerId(for: card)
                )
            }
    }
}
enum ReviewPanelHistoricalFindingsLoader {
    static var fetch: @Sendable (HistoricalFindingsQuery) async -> [HistoricalFindingRecord] = { query in
        VerifiedFindingsQueryService.listHistoricalFindings(query: query)
    }

    static func list(query: HistoricalFindingsQuery) async -> [HistoricalFindingRecord] {
        await Task.detached(priority: .userInitiated) { await fetch(query) }.value
    }
}

private struct ReviewCoreSnapshotHistoryRequest: Encodable {
    let schemaVersion: Int
    let snapshot: CodeReviewSessionSnapshot
}

private struct ReviewCoreReduceHistoryResponse: Decodable {
    let mergedHistory: [HistoricalFindingRecord]
}
