import CoderEngine
import Foundation

enum ReviewPanelStateRustAdapter {
    static func reduce(
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPanelRustPanelState? {
        let response: ReviewPanelReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelReduceRequest(snapshot: snapshot)
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
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
            title: "Unified Review Pipeline",
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

extension String {
    var reviewToolStatus: ReviewPipelineToolExecution.Status {
        switch self {
        case "completed":
            return .completed
        case "running":
            return .running
        default:
            return .pending
        }
    }

    var reviewPanelWarmState: ReviewPanelWarmState {
        switch self {
        case "warming":
            return .warming
        case "failed":
            return .failed
        case "idle":
            return .idle
        default:
            return .ready
        }
    }
}

extension Dictionary where Key == String, Value == Int {
    var findingSeverityCounts: [FindingSeverity: Int] {
        reduce(into: [FindingSeverity: Int]()) { partialResult, entry in
            if let severity = FindingSeverity(rawValue: entry.key) {
                partialResult[severity] = entry.value
            }
        }
    }
}
