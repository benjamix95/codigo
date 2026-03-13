import CoderEngine
import Foundation

enum ReviewPanelHistoryLiveRustAdapter {
    static func derive(
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPanelRustHistoryLiveBoardState? {
        let response: ReviewPanelHistoryLiveReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_history_live",
            request: ReviewPanelHistoryLiveSnapshotRequest(snapshot: snapshot)
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }
}

private struct ReviewPanelHistoryLiveSnapshotRequest: Encodable {
    let schemaVersion: Int = 1
    let snapshot: CodeReviewSessionSnapshot
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
            status: rustStatus(status),
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
            status: rustStatus(status)
        )
    }
}

private func rustStatus(_ status: String) -> SwarmCardStatus {
    switch status {
    case "completed":
        return .completed
    case "running":
        return .running
    case "failed":
        return .failed
    default:
        return .idle
    }
}
