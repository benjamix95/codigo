import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    var historyLiveRefreshKey: String {
        let sessionKey = selectedSessionId ?? "no-session"
        let snapshotKey = currentSnapshot?.lastUpdatedAt.timeIntervalSince1970.description ?? "0"
        let workers = liveReviewWorkers()
        let cards = liveReviewCards()
        let workerKey = workers.map { "\($0.id):\($0.fileCount):\($0.files.joined(separator: ","))" }
            .joined(separator: "|")
        let cardKey = cards.map { "\($0.swarmId):\($0.status.rawValue):\($0.currentStepTitle)" }
            .joined(separator: "|")
        return [findingsHistoryRefreshKey, sessionKey, snapshotKey, workerKey, cardKey].joined(separator: "|")
    }

    var currentHistoricalLiveRunState: ReviewHistoricalLiveBoardState? {
        guard let snapshot = currentSnapshot,
              let pipeline = currentPipelineJobState else {
            return nil
        }

        let workers = liveReviewWorkers()
        let cards = liveReviewCards()
        guard snapshot.isActive
                || snapshot.phase == .completed
                || snapshot.phase == .failed
                || !workers.isEmpty
                || !cards.isEmpty else {
            return nil
        }

        let cardsByWorkerID = Dictionary(uniqueKeysWithValues: cards.compactMap { card in
            liveWorkerIdentifier(for: card).map { ($0, card) }
        })
        let liveWorkers = historicalLiveWorkers(
            workers: workers,
            cardsByWorkerID: cardsByWorkerID,
            snapshot: snapshot
        )
        let files = historicalLiveFiles(from: liveWorkers)

        return ReviewHistoricalLiveBoardState(
            title: snapshot.isActive ? "Live Review Board" : "Completed Run Summary",
            subtitle: snapshot.isActive
                ? "File e worker aggiornati in tempo reale durante la review corrente."
                : "Ultimo run congelato con dettaglio operativo enterprise-grade.",
            pipeline: pipeline,
            workers: liveWorkers,
            files: files,
            isRunning: snapshot.isActive
        )
    }

    private func historicalLiveWorkers(
        workers: [ReviewWorkerRow],
        cardsByWorkerID: [String: SwarmLiveCardState],
        snapshot: CodeReviewSessionSnapshot
    ) -> [ReviewHistoricalLiveWorkerState] {
        if !workers.isEmpty {
            return workers.map { worker in
                let card = cardsByWorkerID[worker.id]
                return ReviewHistoricalLiveWorkerState(
                    id: worker.id,
                    title: worker.id,
                    detail: card?.currentStepTitle ?? worker.description,
                    severity: worker.severity,
                    status: card?.status ?? (snapshot.isActive ? .running : .completed),
                    files: worker.files,
                    fileCount: worker.fileCount
                )
            }
        }

        return liveReviewCards().map { card in
            let fileList = liveFiles(from: card)
            return ReviewHistoricalLiveWorkerState(
                id: liveWorkerIdentifier(for: card) ?? card.swarmId,
                title: card.displayName.isEmpty ? card.swarmId : card.displayName,
                detail: card.currentStepTitle,
                severity: card.warningCount > 0 ? .warning : .info,
                status: card.status,
                files: fileList,
                fileCount: fileList.count
            )
        }
    }

    private func historicalLiveFiles(
        from workers: [ReviewHistoricalLiveWorkerState]
    ) -> [ReviewHistoricalLiveFileState] {
        struct Aggregate {
            var workerIDs: Set<String>
            var severity: FindingSeverity
            var status: SwarmCardStatus
        }

        var aggregates: [String: Aggregate] = [:]
        for worker in workers {
            for path in worker.files where !path.isEmpty {
                if var aggregate = aggregates[path] {
                    aggregate.workerIDs.insert(worker.id)
                    if worker.severity.sortOrder < aggregate.severity.sortOrder {
                        aggregate.severity = worker.severity
                    }
                    aggregate.status = mergedStatus(lhs: aggregate.status, rhs: worker.status)
                    aggregates[path] = aggregate
                } else {
                    aggregates[path] = Aggregate(
                        workerIDs: [worker.id],
                        severity: worker.severity,
                        status: worker.status
                    )
                }
            }
        }

        return aggregates.map { path, aggregate in
            ReviewHistoricalLiveFileState(
                path: path,
                workerIDs: aggregate.workerIDs.sorted(),
                severity: aggregate.severity,
                status: aggregate.status
            )
        }
        .sorted { lhs, rhs in
            if lhs.severity.sortOrder != rhs.severity.sortOrder {
                return lhs.severity.sortOrder < rhs.severity.sortOrder
            }
            return lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
        }
    }

    private func liveWorkerIdentifier(for card: SwarmLiveCardState) -> String? {
        if !card.swarmId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return card.swarmId
        }
        return card.recentEvents.compactMap { event in
            event.payload["worker_id"]
        }.first
    }

    private func liveFiles(from card: SwarmLiveCardState) -> [String] {
        let direct = card.recentEvents
            .compactMap { event -> [String]? in
                let raw = event.payload["files_raw"] ?? event.payload["files"]
                guard let raw, !raw.isEmpty else { return nil }
                return raw
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            .flatMap { $0 }
        return Array(Set(direct)).sorted()
    }

    private func mergedStatus(lhs: SwarmCardStatus, rhs: SwarmCardStatus) -> SwarmCardStatus {
        let rank: [SwarmCardStatus: Int] = [
            .failed: 0,
            .running: 1,
            .completed: 2,
            .idle: 3,
        ]
        return (rank[lhs] ?? 99) <= (rank[rhs] ?? 99) ? lhs : rhs
    }

    private func liveReviewWorkers() -> [ReviewWorkerRow] {
        let reviewActivities = scopedReviewActivitiesForSession(
            taskActivityStore.activities + taskActivityStore.pendingActivities,
            sessionId: selectedSessionId
        )
        let workerActivities = sortedReviewWorkerPlanActivitiesForDisplay(
            selectReviewWorkerActivities(from: reviewActivities)
        )
        return workerActivities.compactMap { activity in
            guard let wid = activity.payload["worker_id"],
                  let desc = activity.payload["description"],
                  let sev = activity.payload["severity"],
                  let fcRaw = activity.payload["fileCount"] else {
                return nil
            }
            let rawFiles = (activity.payload["files_raw"] ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ReviewWorkerRow(
                id: wid,
                description: desc,
                severity: FindingSeverity(rawValue: sev.lowercased()) ?? .warning,
                fileCount: Int(fcRaw) ?? 0,
                files: rawFiles,
                filesSummary: activity.payload["files"] ?? ""
            )
        }
    }

    private func liveReviewCards() -> [SwarmLiveCardState] {
        let sessionId = selectedSessionId
        return taskActivityStore
            .swarmCardStatesIncludingPending(for: conversationId)
            .filter {
                isCodeReviewSwarmCard($0)
                    && reviewCardBelongsToSession($0, sessionId: sessionId)
            }
    }
}
