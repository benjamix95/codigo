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
