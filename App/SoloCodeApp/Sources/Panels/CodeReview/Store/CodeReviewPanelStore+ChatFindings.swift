import CoderEngine
import Foundation

extension CodeReviewPanelStore {
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
