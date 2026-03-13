import CoderEngine
import Foundation

enum ReviewPanelStateRustAdapter {
    static func reduce(snapshot: CodeReviewSessionSnapshot) -> ReviewPanelRustPanelState? {
        let response: ReviewPanelReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelReduceRequest(snapshot: snapshot)
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }

    static let runtimeUnavailableMessage = "Rust review panel runtime required but unavailable."
}

enum ReviewPanelHistoryLiveRustAdapter {
    static func derive(snapshot: CodeReviewSessionSnapshot, workerPlans: [ReviewPanelHistoryWorkerPlanInput], liveCards: [ReviewPanelHistoryLiveCardInput]) -> ReviewPanelRustHistoryLiveBoardState? {
        let response: ReviewPanelHistoryLiveReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_history_live",
            request: ReviewPanelHistoryLiveRequest(
                snapshot: snapshot,
                workerPlans: workerPlans,
                liveCards: liveCards
            )
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }
}

enum ReviewPipelineJobStateBuilder {
    static func build(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .panel
    ) -> ReviewPipelineJobState {
        let pipeline = VerifiedFindingsPipelineStatusService.evaluate(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        let bundleModes = pipeline.bundleModes.isEmpty ? ["standard", "bugFinder", "securityAudit"] : pipeline.bundleModes

        return ReviewPipelineJobState(
            title: "Stato revisione",
            phase: pipeline.pipelinePhase,
            progressPercent: pipeline.progressPercent,
            stepsCompleted: pipeline.stepsCompleted,
            stepsTotal: pipeline.stepsTotal,
            toolsTotal: pipeline.toolsTotal,
            toolsCompleted: pipeline.toolsCompleted,
            toolsRunning: pipeline.toolsRunning,
            candidateCount: pipeline.candidateCount,
            verifiedCount: pipeline.verifiedCount,
            publishedFindingCount: pipeline.publishedFindingCount,
            hiddenFindingCount: max(snapshot.findings.count - pipeline.publishedFindingCount, 0),
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: pipeline.verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: pipeline.patchGateReady),
            ],
            tools: toolExecutions(
                audit: snapshot.audit,
                pipeline: pipeline,
                bundleModes: bundleModes
            ),
            phaseLedger: snapshot.phaseLedger,
            bundleModes: bundleModes,
            isTerminal: snapshot.phase == .completed || snapshot.phase == .failed
        )
    }

    private static func toolExecutions(
        audit: ReviewAuditSnapshot,
        pipeline: VerifiedFindingsPipelineStatus,
        bundleModes: [String]
    ) -> [ReviewPipelineToolExecution] {
        let auditedTools = audit.toolCoverage.keys.sorted().map { toolName in
            ReviewPipelineToolExecution(
                id: toolName,
                title: displayTitle(for: toolName),
                status: .completed,
                findingsCount: audit.toolFindingsCounts[toolName] ?? 0
            )
        }
        if !auditedTools.isEmpty {
            return auditedTools
        }

        return bundleModes.enumerated().map { index, mode in
            let runningThreshold = min(pipeline.toolsRunning, bundleModes.count)
            let status: ReviewPipelineToolExecution.Status
            if index < pipeline.toolsCompleted {
                status = .completed
            } else if index < pipeline.toolsCompleted + runningThreshold {
                status = .running
            } else {
                status = .pending
            }
            return ReviewPipelineToolExecution(
                id: mode,
                title: displayTitle(for: mode),
                status: status,
                findingsCount: 0
            )
        }
    }

    static func displayTitle(for rawValue: String) -> String {
        switch rawValue {
        case "standard": return "Standard Review"
        case "bugFinder": return "Bug Finder"
        case "securityAudit": return "Security Audit"
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }
}

private struct ReviewPanelHistoryLiveRequest: Encodable {
    let schemaVersion: Int = 1
    let snapshot: CodeReviewSessionSnapshot
    let workerPlans: [ReviewPanelHistoryWorkerPlanInput]
    let liveCards: [ReviewPanelHistoryLiveCardInput]
}

private struct ReviewPanelHistoryLiveReduceResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: ReviewPanelRustHistoryLiveBoardState?
}

struct ReviewPanelRustHistoryLiveBoardState: Decodable {
    let title: String
    let subtitle: String
    let workers: [ReviewPanelRustHistoryLiveWorker]
    let files: [ReviewPanelRustHistoryLiveFile]
    let isRunning: Bool

    func makeBoardState(pipeline: ReviewPipelineJobState) -> ReviewHistoricalLiveBoardState {
        ReviewHistoricalLiveBoardState(
            title: title,
            subtitle: subtitle,
            pipeline: pipeline,
            workers: workers.map(\.appModel),
            files: files.map(\.appModel),
            isRunning: isRunning
        )
    }
}

struct ReviewPanelRustHistoryLiveWorker: Decodable {
    let id: String
    let title: String
    let detail: String
    let severity: String
    let status: String
    let files: [String]
    let fileCount: Int

    var appModel: ReviewHistoricalLiveWorkerState {
        ReviewHistoricalLiveWorkerState(
            id: id,
            title: title,
            detail: detail,
            severity: FindingSeverity(rawValue: severity) ?? .info,
            status: reviewRustStatus(status),
            files: files,
            fileCount: fileCount
        )
    }
}

struct ReviewPanelRustHistoryLiveFile: Decodable {
    let path: String
    let workerIds: [String]
    let severity: String
    let status: String

    var appModel: ReviewHistoricalLiveFileState {
        ReviewHistoricalLiveFileState(
            path: path,
            workerIDs: workerIds,
            severity: FindingSeverity(rawValue: severity) ?? .info,
            status: reviewRustStatus(status)
        )
    }
}

private func reviewRustStatus(_ status: String) -> SwarmCardStatus {
    switch status {
    case "completed": return .completed
    case "running": return .running
    case "failed": return .failed
    default: return .idle
    }
}

struct ReviewPanelReduceRequest: Encodable {
    let schemaVersion: Int = 1
    let operation: String = "derive_review_panel_state"
    let snapshot: CodeReviewSessionSnapshot
}

struct ReviewPanelReduceResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: ReviewPanelRustPanelState?
}

struct ReviewPanelReduceError: Decodable {
    let code: String
    let message: String
}

struct ReviewPanelRustPanelState: Decodable {
    let liveCandidateIds: [String]
    let verifiedFindingIds: [String]
    let publishReadyFindingIds: [String]
    let publishedFindingIds: [String]
    let publishedSeverityCounts: [String: Int]
    let pipelinePhase: String
    let progressPercent: Int
    let stepsCompleted: Int
    let stepsTotal: Int
    let toolsTotal: Int
    let toolsCompleted: Int
    let toolsRunning: Int
    let candidateCount: Int
    let verifiedCount: Int
    let publishedFindingCount: Int
    let hiddenFindingCount: Int
    let verificationGateReady: Bool
    let patchGateReady: Bool
    let bundleModes: [String]
    let toolExecutions: [ReviewPanelRustToolExecution]
    let isTerminal: Bool
    let phaseLedger: [ReviewPipelinePhaseLedgerEntry]
    let fileLedger: [ReviewPipelineFileLedgerEntry]
    let warmState: String
    let emptyStateTitle: String
    let emptyStateSubtitle: String

    func makePipelineJobState() -> ReviewPipelineJobState {
        ReviewPipelineJobState(
            title: "Stato revisione",
            phase: pipelinePhase,
            progressPercent: progressPercent,
            stepsCompleted: stepsCompleted,
            stepsTotal: stepsTotal,
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            toolsRunning: toolsRunning,
            candidateCount: candidateCount,
            verifiedCount: verifiedCount,
            publishedFindingCount: publishedFindingCount,
            hiddenFindingCount: hiddenFindingCount,
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: patchGateReady),
            ],
            tools: toolExecutions.map {
                ReviewPipelineToolExecution(
                    id: $0.id,
                    title: ReviewPipelineJobStateBuilder.displayTitle(for: $0.id),
                    status: $0.status.reviewToolStatus,
                    findingsCount: $0.findingsCount
                )
            },
            phaseLedger: phaseLedger,
            bundleModes: bundleModes,
            isTerminal: isTerminal
        )
    }
}

struct ReviewPanelRustToolExecution: Decodable {
    let id: String
    let status: String
    let findingsCount: Int
}
