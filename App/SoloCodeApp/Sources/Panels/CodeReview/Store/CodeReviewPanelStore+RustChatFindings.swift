import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func mergeChatFindingsWithRust(
        existing: [CodeReviewFinding],
        incoming: [CodeReviewFinding]
    ) -> (all: [CodeReviewFinding], insertedCount: Int)? {
        let request = ReviewCoreChatFindingsRequest(
            schemaVersion: 1,
            operation: "merge_chat_findings",
            primary: existing,
            fallback: incoming
        )
        let response: ReviewCoreChatFindingsResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: request
        )
        guard response?.error == nil,
              let payload = response?.panelState else {
            return nil
        }
        return (payload.findings, payload.insertedCount)
    }
}

private struct ReviewCoreChatFindingsRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let primary: [CodeReviewFinding]
    let fallback: [CodeReviewFinding]
}

private struct ReviewCoreChatFindingsResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: ReviewCoreChatFindingsPayload?
}

private struct ReviewCoreChatFindingsPayload: Decodable {
    let findings: [CodeReviewFinding]
    let insertedCount: Int
}
