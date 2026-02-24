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
            existing: "Analisi iniziale",
            incoming: "Nuovo blocco indipendente"
        )

        XCTAssertEqual(merged, "Analisi iniziale\n\nNuovo blocco indipendente")
    }

    func testMergeReasoningDeduplicatesIdenticalChunk() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "Blocco identico",
            incoming: "Blocco identico"
        )

        XCTAssertEqual(merged, "Blocco identico")
    }

    func testMergeReasoningUsesOverlapWhenChunksTouch() {
        let merged = ChatPanelView.mergeReasoningText(
            existing: "alpha-beta",
            incoming: "beta-gamma"
        )

        XCTAssertEqual(merged, "alpha-beta-gamma")
    }
}
