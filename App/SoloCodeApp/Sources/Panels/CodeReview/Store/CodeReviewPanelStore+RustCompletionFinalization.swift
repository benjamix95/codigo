import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func patchFinalizationTargets(
        for snapshot: CodeReviewSessionSnapshot
    ) -> [String]? {
        let response: ReviewPanelPatchFinalizationTargetsResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelPatchFinalizationTargetsRequest(
                schemaVersion: 1,
                operation: "derive_patch_finalization_targets",
                snapshot: snapshot
            )
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }
}

private struct ReviewPanelPatchFinalizationTargetsRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let snapshot: CodeReviewSessionSnapshot
}

private struct ReviewPanelPatchFinalizationTargetsResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: [String]?
}
