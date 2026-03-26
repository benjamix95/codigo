import XCTest
@testable import CoderIDE

final class ChatTurnTimelineInterleaverTests: XCTestCase {
    func testEmptyInputsReturnEmptySegments() {
        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: [],
            traceEvents: []
        )

        XCTAssertTrue(segments.isEmpty)
    }

    func testTextBlocksCreateTextSegments() {
        let blocks = [
            makeBlock(kind: .primaryText, text: "Hello world", sequence: 0),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertEqual(segments.count, 1)
        if case .text(_, let content, let seq) = segments.first {
            XCTAssertEqual(content, "Hello world")
            XCTAssertEqual(seq, 0)
        } else {
            XCTFail("Expected .text segment")
        }
    }

    func testEmptyPrimaryTextBlocksAreFiltered() {
        let blocks = [
            makeBlock(kind: .primaryText, text: "   \n  ", sequence: 0),
            makeBlock(kind: .primaryText, text: "Visible", sequence: 1),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertEqual(segments.count, 1)
    }

    func testReasoningBlocksCreateReasoningSegments() {
        let blocks = [
            makeBlock(kind: .reasoning, text: "Thinking...", sequence: 0),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertEqual(segments.count, 1)
        if case .reasoning(_, let text, _) = segments.first {
            XCTAssertEqual(text, "Thinking...")
        } else {
            XCTFail("Expected .reasoning segment")
        }
    }

    func testReasoningBlocksSkippedWhenSuppressed() {
        let blocks = [
            makeBlock(kind: .reasoning, text: "Hidden", sequence: 0),
            makeBlock(kind: .primaryText, text: "Answer", sequence: 1),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: [],
            suppressReasoningBlocks: true
        )

        XCTAssertEqual(segments.count, 1)
        if case .text(_, let content, _) = segments.first {
            XCTAssertEqual(content, "Answer")
        } else {
            XCTFail("Expected only .text segment")
        }
    }

    func testToolMarkerBlocksAreSkipped() {
        let blocks = [
            makeBlock(kind: .toolMarker, text: "marker", sequence: 0),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertTrue(segments.isEmpty)
    }

    func testSegmentsAreSortedBySequence() {
        let blocks = [
            makeBlock(kind: .primaryText, text: "Second", sequence: 2),
            makeBlock(kind: .reasoning, text: "First", sequence: 1),
            makeBlock(kind: .primaryText, text: "Third", sequence: 3),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].sequence, 1)
        XCTAssertEqual(segments[1].sequence, 2)
        XCTAssertEqual(segments[2].sequence, 3)
    }

    func testDefaultBlocksCreateArtifactSegments() {
        let blocks = [
            makeBlock(kind: .mermaid, text: "graph TD; A-->B", sequence: 0),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: []
        )

        XCTAssertEqual(segments.count, 1)
        if case .artifact = segments.first {
            // OK
        } else {
            XCTFail("Expected .artifact segment for non-standard block kinds")
        }
    }

    // MARK: - Helpers

    private func makeBlock(
        kind: ChatTimelineBlockKind,
        text: String = "",
        sequence: Int
    ) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: UUID().uuidString,
            kind: kind,
            text: text,
            sequence: sequence
        )
    }
}
