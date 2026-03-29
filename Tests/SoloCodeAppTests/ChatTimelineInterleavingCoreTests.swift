import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingCoreTests: ChatTimelineInterleavingTestCase {
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

    func testInterleavedSegmentsSortBySequence() {
        let segments: [ChatTurnInterleavedSegment] = [
            .toolEvent(
                id: "trace",
                event: makeEvent(sequence: 1, title: "Read"),
                sequence: 1
            ),
            .text(id: "t0", content: "First", sequence: 0),
            .text(id: "t1", content: "Second", sequence: 2),
        ]
        let sorted = segments.sorted { $0.sequence < $1.sequence }
        XCTAssertEqual(sorted.map(\.sequence), [0, 1, 2])
    }

    func testInterleavedSegmentTextContent() {
        let segment = ChatTurnInterleavedSegment.text(id: "t1", content: "Hello", sequence: 42)
        if case .text(_, let content, let sequence) = segment {
            XCTAssertEqual(content, "Hello")
            XCTAssertEqual(sequence, 42)
        } else {
            XCTFail("Expected text segment")
        }
    }

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

    func testMultipleTextBlocksWithDifferentSequences() {
        let blocks = [
            makeBlock(id: "text-seg-0", kind: .primaryText, text: "First", sequence: 0),
            makeBlock(id: "text-seg-1", kind: .primaryText, text: "Second", sequence: 2),
        ]
        let textBlocks = blocks.filter { $0.kind == .primaryText }
        XCTAssertEqual(textBlocks.count, 2)
        XCTAssertEqual(textBlocks.map(\.sequence), [0, 2])
    }

    func testToolMarkerBlocksFilteredInView() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            makeBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            makeBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 2),
        ]
        let visible = blocks.filter { $0.kind != .toolMarker }
        let markers = blocks.filter { $0.kind == .toolMarker }
        XCTAssertEqual(visible.count, 2)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].sequence, 1)
    }

    func testInterleaverReasoningBeforeTextWhenSequenceEqualRegardlessOfId() {
        let blocks = [
            makeBlock(id: "aaaa-text", kind: .primaryText, text: "Answer", sequence: 0),
            makeBlock(id: "zzzz-reason", kind: .reasoning, text: "Think", sequence: 0),
        ]
        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: [])
        XCTAssertEqual(segments.count, 2)
        if case .reasoning(let id, let text, let seq) = segments[0] {
            XCTAssertEqual(seq, 0)
            XCTAssertEqual(id, "zzzz-reason")
            XCTAssertEqual(text, "Think")
        } else {
            XCTFail("Reasoning should precede text when sequence is equal")
        }
    }

    func testInterleaverUsesTimestampAsSecondarySortForEqualSequenceEvents() {
        let earlier = makeEvent(
            sequence: 1,
            title: "Read A",
            path: "/tmp/A.swift",
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let later = makeEvent(
            sequence: 1,
            title: "Read B",
            path: "/tmp/B.swift",
            timestamp: Date(timeIntervalSince1970: 20)
        )

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: [makeBlock(kind: .primaryText, text: "Hi", sequence: 0)],
            traceEvents: [later, earlier]
        )

        let toolTitles = segments.flatMap { segment -> [String] in
            switch segment {
            case .toolEvent(_, let event, _):
                return [event.title]
            case .toolGroup(_, let group, _):
                return group.events.map(\.title)
            default:
                return []
            }
        }
        XCTAssertEqual(toolTitles, ["Read A", "Read B"])
    }
}
