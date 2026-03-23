import XCTest
@testable import CoderIDE

final class ChatPanelReasoningMergeTests: XCTestCase {
    func testMergeReasoningReplacesWhenIncomingExtendsExisting() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "Step 1",
            incoming: "Step 1\nStep 2"
        )

        XCTAssertEqual(merged, "Step 1\nStep 2")
    }

    func testMergeReasoningAppendsIndependentChunks() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "Initial analysis",
            incoming: "New independent block"
        )

        XCTAssertEqual(merged, "Initial analysis\n\nNew independent block")
    }

    func testMergeReasoningDeduplicatesIdenticalChunk() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "Identical block",
            incoming: "Identical block"
        )

        XCTAssertEqual(merged, "Identical block")
    }

    func testMergeReasoningUsesOverlapWhenChunksTouch() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "alpha-beta",
            incoming: "beta-gamma"
        )

        XCTAssertEqual(merged, "alpha-beta-gamma")
    }

    func testFinalAssistantContentExcludingReasoningRemovesDuplicateBody() {
        XCTAssertEqual(
            finalAssistantContentExcludingReasoning(
                fullText: "Planning next move",
                reasoningText: "Planning next move"
            ),
            ""
        )
    }

    func testFinalAssistantContentExcludingReasoningKeepsTailAfterReasoning() {
        XCTAssertEqual(
            finalAssistantContentExcludingReasoning(
                fullText: "Planning next move\n\nFinal answer",
                reasoningText: "Planning next move"
            ),
            "Final answer"
        )
    }
}
