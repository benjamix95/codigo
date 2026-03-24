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
            .toolEvent(
                id: "trace",
                event: ToolTraceEvent(
                    sequence: 1,
                    timestamp: Date(timeIntervalSince1970: 1),
                    providerId: "codex-cli",
                    conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                    assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    type: "mcp_tool_call",
                    title: "Read",
                    detail: nil,
                    payload: [:],
                    phase: .executing,
                    isRunning: false,
                    groupId: nil,
                    rawKind: "raw"
                ),
                sequence: 1
            ),
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

    func testInterleaverEmitsOneToolSegmentPerEvent() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file"),
            makeEvent(sequence: 2, title: "Search symbol"),
            makeEvent(sequence: 3, title: "Write patch"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let toolSegments = segments.compactMap { segment -> ToolTraceEvent? in
            if case .toolEvent(_, let event, _) = segment { return event }
            return nil
        }

        XCTAssertEqual(toolSegments.map(\.title), ["Read file", "Search symbol", "Write patch"])
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2, 3, 4])
    }

    func testInterleaverPlacesLiveSubagentCardInlineUsingMatchingSwarmSequence() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 2, title: "Spawn reviewer", swarmId: "sa-review"),
            makeEvent(sequence: 3, title: "Reviewer update", swarmId: "sa-review"),
        ]
        let liveCards = [
            SwarmLiveCardState(
                swarmId: "sa-review",
                displayName: "Reviewer",
                roleType: "reviewer"
            )
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: events,
            liveSubagentCards: liveCards
        )

        let liveCardSequences = segments.compactMap { segment -> Int? in
            if case .subagentLiveCard(_, let card, let sequence) = segment, card.swarmId == "sa-review" {
                return sequence
            }
            return nil
        }

        XCTAssertEqual(liveCardSequences, [2])
    }

    private func makeEvent(sequence: Int, title: String, swarmId: String? = nil) -> ToolTraceEvent {
        var payload = ["mcp_tool": "read"]
        if let swarmId {
            payload["swarm_id"] = swarmId
        }
        return ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: "mcp_tool_call",
            title: title,
            detail: nil,
            payload: payload,
            phase: .executing,
            isRunning: false,
            groupId: nil,
            rawKind: "raw"
        )
    }
}
