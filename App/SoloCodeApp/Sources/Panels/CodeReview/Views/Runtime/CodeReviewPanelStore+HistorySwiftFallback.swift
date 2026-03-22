import CoderEngine
import Foundation

/// Swift fallback for `ReviewPanelHistoryLiveRustAdapter.derive()`
/// when the Rust bridge is unavailable or returns nil.
enum ReviewPanelHistoryLiveSwiftFallback {
    static func derive(
        snapshot: CodeReviewSessionSnapshot,
        workerPlans: [ReviewPanelHistoryWorkerPlanInput],
        liveCards: [ReviewPanelHistoryLiveCardInput],
        pipeline: ReviewPipelineJobState
    ) -> ReviewHistoricalLiveBoardState? {
        let isRunning = snapshot.isActive
        let title = isRunning ? "Live Review Board" : "Completed Run Summary"
        let subtitle = isRunning
            ? "\(workerPlans.count) worker(s) active"
            : "Round \(snapshot.currentRound)"

        let workers: [ReviewHistoricalLiveWorkerState]
        let files: [ReviewHistoricalLiveFileState]

        if !snapshot.fileLedger.isEmpty {
            let ledgerWorkers = deriveLedgerWorkers(from: snapshot.fileLedger)
            let ledgerFiles = deriveLedgerFiles(from: snapshot.fileLedger)
            workers = ledgerWorkers
            files = ledgerFiles
        } else {
            workers = deriveWorkers(from: workerPlans)
            files = deriveFiles(from: workerPlans)
        }

        return ReviewHistoricalLiveBoardState(
            title: title,
            subtitle: subtitle,
            pipeline: pipeline,
            workers: workers,
            files: files,
            isRunning: isRunning
        )
    }

    // MARK: - Worker Plans

    private static func deriveWorkers(
        from plans: [ReviewPanelHistoryWorkerPlanInput]
    ) -> [ReviewHistoricalLiveWorkerState] {
        plans.map { plan in
            ReviewHistoricalLiveWorkerState(
                id: plan.workerId,
                title: plan.workerId,
                detail: plan.description,
                severity: FindingSeverity(rawValue: plan.severity) ?? .info,
                status: .running,
                files: plan.files,
                fileCount: plan.fileCount
            )
        }
    }

    private static func deriveFiles(
        from plans: [ReviewPanelHistoryWorkerPlanInput]
    ) -> [ReviewHistoricalLiveFileState] {
        var fileMap: [(path: String, workerIds: [String], severity: FindingSeverity)] = []
        var seen: [String: Int] = [:]

        for plan in plans {
            let severity = FindingSeverity(rawValue: plan.severity) ?? .info
            for file in plan.files {
                if let idx = seen[file] {
                    fileMap[idx].workerIds.append(plan.workerId)
                    if severityRank(severity) < severityRank(fileMap[idx].severity) {
                        fileMap[idx].severity = severity
                    }
                } else {
                    seen[file] = fileMap.count
                    fileMap.append((path: file, workerIds: [plan.workerId], severity: severity))
                }
            }
        }

        return fileMap
            .sorted { severityRank($0.severity) < severityRank($1.severity) }
            .map { entry in
                ReviewHistoricalLiveFileState(
                    path: entry.path,
                    workerIDs: entry.workerIds,
                    severity: entry.severity,
                    status: .running
                )
            }
    }

    // MARK: - Ledger

    private static func deriveLedgerWorkers(
        from ledger: [ReviewPipelineFileLedgerEntry]
    ) -> [ReviewHistoricalLiveWorkerState] {
        var workerMap: [String: ReviewHistoricalLiveWorkerState] = [:]
        for entry in ledger {
            for workerId in entry.workerIds {
                if workerMap[workerId] == nil {
                    workerMap[workerId] = ReviewHistoricalLiveWorkerState(
                        id: workerId,
                        title: workerId,
                        detail: entry.phaseId,
                        severity: entry.severity ?? .info,
                        status: swarmStatus(from: entry.status),
                        files: [entry.path],
                        fileCount: 1
                    )
                }
            }
        }
        return Array(workerMap.values)
    }

    private static func deriveLedgerFiles(
        from ledger: [ReviewPipelineFileLedgerEntry]
    ) -> [ReviewHistoricalLiveFileState] {
        ledger
            .sorted { severityRank($0.severity ?? .info) < severityRank($1.severity ?? .info) }
            .map { entry in
                ReviewHistoricalLiveFileState(
                    path: entry.path,
                    workerIDs: entry.workerIds,
                    severity: entry.severity ?? .info,
                    status: swarmStatus(from: entry.status)
                )
            }
    }

    // MARK: - Helpers

    private static func swarmStatus(
        from ledgerStatus: ReviewPipelineLedgerStatus
    ) -> SwarmCardStatus {
        switch ledgerStatus {
        case .running: return .running
        case .completed: return .completed
        case .blocked: return .failed
        case .pending: return .idle
        }
    }

    private static func severityRank(_ severity: FindingSeverity) -> Int {
        switch severity {
        case .critical: return 0
        case .warning: return 1
        case .suggestion: return 2
        case .info: return 3
        }
    }
}

/// Swift fallback for deriving `HistoricalFindingRecord` from snapshots
/// when the Rust bridge is unavailable or returns nil.
enum ReviewPanelHistorySwiftFallback {
    static func deriveHistoricalFindings(
        from snapshot: CodeReviewSessionSnapshot
    ) -> [HistoricalFindingRecord]? {
        guard !snapshot.findings.isEmpty else { return nil }
        let patchById = Dictionary(
            uniqueKeysWithValues: snapshot.patches.map { ($0.id, $0) }
        )
        let patchByFinding = Dictionary(
            uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) }
        )
        return snapshot.findings.map { finding in
            let patch = finding.patchArtifactId.flatMap { patchById[$0] }
                ?? patchByFinding[finding.id]
            return HistoricalFindingRecord(
                findingId: finding.id,
                sessionId: snapshot.sessionId,
                workspaceId: snapshot.workspacePath ?? "",
                domain: mapDomain(finding.category),
                severity: mapSeverity(finding.severity),
                title: finding.message,
                summary: finding.verificationReport ?? finding.message,
                status: mapStatus(finding: finding, patch: patch),
                filePath: finding.filePath,
                lineStart: finding.lineNumber,
                sourceOrigin: finding.origin.rawValue,
                closedReason: closedReason(for: finding.status),
                patchId: patch?.id,
                patchApplyStatus: mapPatchApplyStatus(patch: patch, findingStatus: finding.status),
                revalidationReportId: nil,
                revalidationVerdict: nil,
                createdAt: finding.createdAt,
                updatedAt: patch?.updatedAt ?? finding.verifiedAt ?? finding.createdAt,
                resolvedAt: resolvedDate(for: finding),
                resumeEligible: finding.status == .open,
                timeline: []
            )
        }
    }

    private static func mapDomain(_ category: FindingCategory) -> VerifiedFindingDomain {
        switch category {
        case .security: return .security
        default: return .bug
        }
    }

    private static func mapSeverity(_ severity: FindingSeverity) -> VerifiedFindingSeverity {
        switch severity {
        case .critical: return .critical
        case .warning: return .medium
        case .suggestion: return .low
        case .info: return .info
        }
    }

    private static func mapStatus(
        finding: CodeReviewFinding,
        patch: ReviewPatchArtifact?
    ) -> VerifiedFindingStatus {
        switch finding.status {
        case .open:
            if finding.verifiedAt != nil { return .verified }
            return .candidate
        case .fixApplied: return .patchApplied
        case .patchPreparing: return .patchPreparing
        case .patchReady: return .patchPrepared
        case .patchApplying: return .patchApplied
        case .patchApplied:
            if let patch, patch.validationStatus == .passed {
                return .fixedVerified
            }
            return .patchApplied
        case .patchFailed: return .fixFailed
        case .prOpened: return .patchApplied
        case .merged: return .fixedVerified
        case .blocked: return .needsManualReview
        case .dismissed, .wontFix: return .closed
        case .closed: return .closed
        }
    }

    private static func mapPatchApplyStatus(
        patch: ReviewPatchArtifact?,
        findingStatus: FindingStatus
    ) -> VerifiedPatchApplyStatus? {
        if let patch {
            switch patch.status {
            case .applied: return .applied
            case .applyFailed: return .failed
            case .rolledBack: return .rolledBack
            default:
                if findingStatus == .patchApplied { return .applied }
                return nil
            }
        }
        switch findingStatus {
        case .patchApplied, .fixApplied: return .applied
        case .patchFailed: return .failed
        default: return nil
        }
    }

    private static func closedReason(for status: FindingStatus) -> String? {
        switch status {
        case .wontFix: return "wont_fix"
        case .dismissed: return "dismissed"
        case .closed: return "closed"
        default: return nil
        }
    }

    private static func resolvedDate(for finding: CodeReviewFinding) -> Date? {
        switch finding.status {
        case .closed, .dismissed, .wontFix, .merged:
            return finding.verifiedAt ?? finding.createdAt
        default: return nil
        }
    }
}
