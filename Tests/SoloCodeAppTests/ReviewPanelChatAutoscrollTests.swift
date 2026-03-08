import XCTest
@testable import CoderIDE

@MainActor
final class ReviewPanelChatAutoscrollTests: XCTestCase {
    func testMessageListFingerprintChangesWhenStructuredPresentationGrows() {
        let messageId = UUID()
        let base = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "### Activity\nReview stream started",
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "activity",
                        title: "Activity",
                        lines: ["Review stream started"],
                        style: .log,
                        isInitiallyExpanded: true
                    )
                ]
            ),
            isStreaming: true
        )

        let updated = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: base.content,
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "activity",
                        title: "Activity",
                        lines: [
                            "Review stream started",
                            "mcp_tool_call: MCP call • coderide/coderide_skill",
                        ],
                        style: .log,
                        isInitiallyExpanded: true
                    )
                ]
            ),
            isStreaming: true
        )

        let before = ReviewPanelChatAutoscroll.messageListFingerprint([base])
        let after = ReviewPanelChatAutoscroll.messageListFingerprint([updated])

        XCTAssertNotEqual(before, after)
    }

    func testMessageListFingerprintChangesWhenStreamingStateFlips() {
        let messageId = UUID()
        let streaming = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "done",
            isStreaming: true
        )
        let completed = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "done",
            isStreaming: false
        )

        XCTAssertNotEqual(
            ReviewPanelChatAutoscroll.messageListFingerprint([streaming]),
            ReviewPanelChatAutoscroll.messageListFingerprint([completed])
        )
    }

    func testSectionLogFingerprintChangesWhenLastLineAdvances() {
        let initial = ReviewPanelChatStructuredSection(
            id: "activity",
            title: "Activity",
            lines: ["Review stream started"],
            style: .log,
            isInitiallyExpanded: true
        )
        let updated = ReviewPanelChatStructuredSection(
            id: "activity",
            title: "Activity",
            lines: [
                "Review stream started",
                "assistant_update: Sto facendo convergere anche il workflow del `skill`",
            ],
            style: .log,
            isInitiallyExpanded: true
        )

        XCTAssertNotEqual(
            ReviewPanelChatAutoscroll.sectionLogFingerprint(initial),
            ReviewPanelChatAutoscroll.sectionLogFingerprint(updated)
        )
    }
}
