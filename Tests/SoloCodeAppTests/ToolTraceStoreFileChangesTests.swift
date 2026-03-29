import XCTest
@testable import CoderIDE

@MainActor
final class ToolTraceStoreFileChangesTests: XCTestCase {
    func testConversationLatestPreviewableFileChangeUsesCollectedPreview() {
        let store = ToolTraceStore()
        let conversationId = UUID()
        let assistantMessageId = UUID()

        store.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: "codex-cli"
        )

        store.append(
            event: makeEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                sequence: 1,
                payload: [
                    "path": "App/SoloCodeApp/Sources/A.swift",
                    "diffPreview": "@@ -1 +1 @@\n-old\n+new",
                ],
                isRunning: true
            )
        )
        store.append(
            event: makeEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                sequence: 2,
                payload: [
                    "path": "App/SoloCodeApp/Sources/A.swift",
                    "linesAdded": "8",
                    "linesRemoved": "2",
                ],
                isRunning: false
            )
        )

        let latest = store.conversationLatestPreviewableFileChange(conversationId: conversationId)

        XCTAssertEqual(latest?.basename, "A.swift")
        XCTAssertEqual(latest?.added, 8)
        XCTAssertEqual(latest?.removed, 2)
        XCTAssertEqual(latest?.compactPreviewText(limit: 2), "-old\n+new")
    }

    private func makeEvent(
        conversationId: UUID,
        assistantMessageId: UUID,
        sequence: Int,
        payload: [String: String],
        isRunning: Bool
    ) -> ToolTraceEvent {
        ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            type: "file_change",
            title: "Edited A.swift",
            detail: nil,
            payload: payload,
            phase: .editing,
            isRunning: isRunning,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
