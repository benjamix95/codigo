import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingTests: XCTestCase {

    // MARK: - ChatTimelineBlockKind

    func testToolMarkerKindDecodesFromRust() {
        let json = """
        {"id":"tool-marker-1","kind":"toolMarker","text":"","items":[],"metadata":{},"isCollapsible":false,"isCollapsedByDefault":false,"sequence":3}
        """.data(using: .utf8)!
        let block = try? JSONDecoder().decode(PersistedChatTimelineBlock.self, from: json)
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.kind, .toolMarker)
        XCTAssertEqual(block?.sequence, 3)
    }

    func testPrimaryTextBlockPreservesSequence() {
        let block = PersistedChatTimelineBlock(
            id: "text-seg-0",
            kind: .primaryText,
            text: "Hello",
            sequence: 5
        )
        XCTAssertEqual(block.sequence, 5)
    }

    func testSequenceDefaultsToZero() {
        let block = PersistedChatTimelineBlock(
            id: "legacy",
            kind: .primaryText,
            text: "Old"
        )
        XCTAssertEqual(block.sequence, 0)
    }

    // MARK: - Interleaved Segment Sorting

    func testInterleavedSegmentsSortBySequence() {
        let segments: [ChatTurnInterleavedSegment] = [
            .toolTrace(id: "trace", events: [], sequence: 1),
            .text(id: "t0", content: "First", sequence: 0),
            .text(id: "t1", content: "Second", sequence: 2),
        ]
        let sorted = segments.sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(sorted[0].sequence, 0)
        XCTAssertEqual(sorted[1].sequence, 1)
        XCTAssertEqual(sorted[2].sequence, 2)
    }

    func testInterleavedSegmentTextContent() {
        let seg = ChatTurnInterleavedSegment.text(id: "t1", content: "Hello", sequence: 42)
        if case .text(_, let content, _) = seg {
            XCTAssertEqual(content, "Hello")
        } else {
            XCTFail("Expected text segment")
        }
        XCTAssertEqual(seg.sequence, 42)
    }

    // MARK: - Bridge Decoding

    func testBridgeBlockWithSequenceDecodes() {
        let json = """
        {"id":"text-seg-0","kind":"primaryText","title":null,"text":"Hello","items":[],"metadata":{},"isCollapsible":false,"isCollapsedByDefault":false,"sequence":7}
        """.data(using: .utf8)!
        let bridge = try? JSONDecoder().decode(MainChatStoreTimelineBlockSnapshotBridge.self, from: json)
        XCTAssertNotNil(bridge)
        XCTAssertEqual(bridge?.sequence, 7)
    }

    func testBridgeBlockWithoutSequenceDefaultsToNil() {
        let json = """
        {"id":"legacy","kind":"primaryText","title":null,"text":"Old","items":[],"metadata":{},"isCollapsible":false,"isCollapsedByDefault":false}
        """.data(using: .utf8)!
        let bridge = try? JSONDecoder().decode(MainChatStoreTimelineBlockSnapshotBridge.self, from: json)
        XCTAssertNotNil(bridge)
        XCTAssertNil(bridge?.sequence)
    }

    // MARK: - Multiple Text Blocks

    func testMultipleTextBlocksWithDifferentSequences() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-seg-0", kind: .primaryText, text: "First", sequence: 0),
            PersistedChatTimelineBlock(id: "text-seg-1", kind: .primaryText, text: "Second", sequence: 2),
        ]
        let textBlocks = blocks.filter { $0.kind == .primaryText }
        XCTAssertEqual(textBlocks.count, 2)
        XCTAssertEqual(textBlocks[0].sequence, 0)
        XCTAssertEqual(textBlocks[1].sequence, 2)
    }

    func testToolMarkerBlocksFilteredInView() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 2),
        ]
        let visible = blocks.filter { $0.kind != .toolMarker }
        XCTAssertEqual(visible.count, 2)
        let markers = blocks.filter { $0.kind == .toolMarker }
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].sequence, 1)
    }
}
