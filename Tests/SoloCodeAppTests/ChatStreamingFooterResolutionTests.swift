import XCTest
@testable import CoderIDE

final class ChatStreamingFooterResolutionTests: XCTestCase {
    func testResolutionFallsBackToRuntimeStatusWhenSnapshotIsNotActive() {
        let message = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "",
            isStreaming: true
        )
        let last = message

        let resolution = resolveChatStreamingFooterResolution(
            displayMessage: message,
            isLastAssistant: true,
            lastMessage: last,
            isLoadingForCurrentConversation: true,
            snapshotIsLoading: false,
            snapshotActiveAssistantMessageId: nil,
            snapshotStreamingStatusText: "",
            snapshotStreamingDetailText: nil,
            fallbackStatusText: "Searching codebase",
            fallbackDetailText: "TaskActivityStore"
        )

        XCTAssertTrue(resolution.shouldComputeText)
        XCTAssertTrue(resolution.isActuallyLoading)
        XCTAssertFalse(resolution.usesSnapshot)
        XCTAssertEqual(resolution.statusText, "Searching codebase")
        XCTAssertEqual(resolution.detailText, "TaskActivityStore")
    }

    func testResolutionPrefersSnapshotForActiveStreamingAssistant() {
        let messageId = UUID()
        let message = ChatMessage(
            id: messageId,
            role: .assistant,
            content: "",
            isStreaming: true
        )

        let resolution = resolveChatStreamingFooterResolution(
            displayMessage: message,
            isLastAssistant: true,
            lastMessage: message,
            isLoadingForCurrentConversation: true,
            snapshotIsLoading: true,
            snapshotActiveAssistantMessageId: messageId,
            snapshotStreamingStatusText: "Planning next move",
            snapshotStreamingDetailText: "Open Debug Session",
            fallbackStatusText: "Thinking",
            fallbackDetailText: "Fallback"
        )

        XCTAssertTrue(resolution.shouldComputeText)
        XCTAssertTrue(resolution.isActuallyLoading)
        XCTAssertTrue(resolution.usesSnapshot)
        XCTAssertEqual(resolution.statusText, "Planning next move")
        XCTAssertEqual(resolution.detailText, "Open Debug Session")
    }
}
