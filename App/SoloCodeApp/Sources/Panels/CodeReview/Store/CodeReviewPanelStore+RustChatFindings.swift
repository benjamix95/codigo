import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func extractAndMergeChatFindingsWithRust(
        content: String,
        existing: [CodeReviewFinding]
    ) -> ReviewCoreChatExtractionPayload? {
        let request = ReviewCoreChatExtractionRequest(
            schemaVersion: 1,
            content: content,
            existingFindings: existing
        )
        let response: ReviewCoreChatExtractionResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_chat_extract",
            request: request
        )
        guard response?.error == nil,
              let payload = response?.payload,
              payload.foundBlock else {
            return nil
        }
        return payload
    }
}

private struct ReviewCoreChatExtractionRequest: Encodable {
    let schemaVersion: Int
    let content: String
    let existingFindings: [CodeReviewFinding]
}

private struct ReviewCoreChatExtractionResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let foundBlock: Bool
    let visibleContent: String
    let findings: [CodeReviewFinding]
    let insertedCount: Int
    let extractedCount: Int

    var payload: ReviewCoreChatExtractionPayload {
        ReviewCoreChatExtractionPayload(
            foundBlock: foundBlock,
            visibleContent: visibleContent,
            findings: findings,
            insertedCount: insertedCount,
            extractedCount: extractedCount
        )
    }
}

struct ReviewCoreChatExtractionPayload {
    let foundBlock: Bool
    let visibleContent: String
    let findings: [CodeReviewFinding]
    let insertedCount: Int
    let extractedCount: Int
}
