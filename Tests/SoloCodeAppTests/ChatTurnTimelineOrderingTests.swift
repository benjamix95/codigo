import XCTest
@testable import CoderIDE

final class ChatTurnTimelineOrderingTests: XCTestCase {
    func testVisibleBlocksFiltersOutToolTraceCommandsFilesStatus() {
        let blocks: [PersistedChatTimelineBlock] = [
            makeBlock(kind: .primaryText, sequence: 0),
            makeBlock(kind: .reasoning, sequence: 1),
            makeBlock(kind: .toolTrace, sequence: 2),
            makeBlock(kind: .commands, sequence: 3),
            makeBlock(kind: .files, sequence: 4),
            makeBlock(kind: .status, sequence: 5),
            makeBlock(kind: .toolMarker, sequence: 6),
        ]

        let visible = ChatTurnTimelineOrdering.visibleBlocks(from: blocks)

        XCTAssertEqual(visible.count, 3)
        XCTAssertTrue(visible.contains { $0.kind == .primaryText })
        XCTAssertTrue(visible.contains { $0.kind == .reasoning })
        XCTAssertTrue(visible.contains { $0.kind == .toolMarker })
        XCTAssertFalse(visible.contains { $0.kind == .toolTrace })
        XCTAssertFalse(visible.contains { $0.kind == .commands })
        XCTAssertFalse(visible.contains { $0.kind == .files })
        XCTAssertFalse(visible.contains { $0.kind == .status })
    }

    func testNarrativeBlocksReturnsOnlyReasoning() {
        let blocks: [PersistedChatTimelineBlock] = [
            makeBlock(kind: .primaryText, sequence: 0),
            makeBlock(kind: .reasoning, sequence: 1),
            makeBlock(kind: .reasoning, sequence: 2),
        ]

        let narrative = ChatTurnTimelineOrdering.narrativeBlocks(from: blocks)

        XCTAssertEqual(narrative.count, 2)
        XCTAssertTrue(narrative.allSatisfy { $0.kind == .reasoning })
    }

    func testDetailBlocksExcludesPrimaryTextAndReasoning() {
        let blocks: [PersistedChatTimelineBlock] = [
            makeBlock(kind: .primaryText, sequence: 0),
            makeBlock(kind: .reasoning, sequence: 1),
            makeBlock(kind: .toolMarker, sequence: 2),
        ]

        let details = ChatTurnTimelineOrdering.detailBlocks(from: blocks)

        XCTAssertEqual(details.count, 1)
        XCTAssertEqual(details.first?.kind, .toolMarker)
    }

    func testVisibleBlocksPreservesOrder() {
        let blocks: [PersistedChatTimelineBlock] = [
            makeBlock(kind: .primaryText, sequence: 0),
            makeBlock(kind: .toolTrace, sequence: 1),
            makeBlock(kind: .reasoning, sequence: 2),
            makeBlock(kind: .status, sequence: 3),
            makeBlock(kind: .primaryText, sequence: 4),
        ]

        let visible = ChatTurnTimelineOrdering.visibleBlocks(from: blocks)

        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible[0].sequence, 0)
        XCTAssertEqual(visible[1].sequence, 2)
        XCTAssertEqual(visible[2].sequence, 4)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(ChatTurnTimelineOrdering.visibleBlocks(from: []).isEmpty)
        XCTAssertTrue(ChatTurnTimelineOrdering.narrativeBlocks(from: []).isEmpty)
        XCTAssertTrue(ChatTurnTimelineOrdering.detailBlocks(from: []).isEmpty)
    }

    // MARK: - Helpers

    private func makeBlock(
        kind: ChatTimelineBlockKind,
        sequence: Int
    ) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: UUID().uuidString,
            kind: kind,
            text: "test-\(sequence)",
            sequence: sequence
        )
    }
}
