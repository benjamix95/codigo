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

    func syncStructuredFindingsFromChatResponse(
        messageId: UUID,
        sessionId: String? = nil
    ) async {
        guard let index = chatMessages.firstIndex(where: { $0.id == messageId }) else {
            return
        }
        let originalContent = chatMessages[index].content
        guard let sessionId = sessionId ?? selectedSessionId,
              let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
              ),
              let extraction = extractAndMergeChatFindingsWithRust(
                content: originalContent,
                existing: snapshot.findings
              ) else {
            return
        }

        chatMessages[index].content = extraction.visibleContent
        persistChatState()

        guard extraction.insertedCount > 0 else {
            return
        }

        let existingCount = snapshot.findings.count
        let inserted = Array(extraction.findings.dropFirst(existingCount))
        let events = inserted.map {
            CodeReviewSessionEvent.findingAdded(
                findingId: $0.id,
                severity: $0.severity.rawValue,
                filePath: $0.filePath
            )
        }
        let updated = snapshot.copying(
            findings: extraction.findings,
            events: snapshot.events + events,
            outcome: snapshot.copying(findings: extraction.findings).buildOutcomeSummary()
        )
        taskActivityStore.ingestCodeReviewSnapshot(
            updated,
            conversationId: conversationId
        )
        appendPanelSystemMessage(
            "Synced \(extraction.insertedCount) finding(s) from chat into the Findings tab.",
            kind: .statusNote,
            selectChatTab: false
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
