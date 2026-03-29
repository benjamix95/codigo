import XCTest
@testable import CoderIDE

final class ChatTimelineInterleavingSyntheticTests: ChatTimelineInterleavingTestCase {
    func testInterleaverKeepsSinglePrimaryBeforeToolsWhenNoToolMarkers() {
        let blocks = [
            makeBlock(id: "text-0", kind: .primaryText, text: "Riepilogo", sequence: 0),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "Write patch", tool: "write", path: "/tmp/B.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)

        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2])
        if case .text(_, let content, let seq) = segments[0] {
            XCTAssertEqual(seq, 0)
            XCTAssertEqual(content, "Riepilogo")
        } else {
            XCTFail("Expected text segment first")
        }
    }

    func testSyntheticFallbackPreservesMultiplePrimaryBlocksWithoutToolMarkers() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let base = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "Prima parte\n\nSeconda parte",
            primaryTextSnapshot: "Prima parte\n\nSeconda parte",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
                makeBlock(id: "text-1", kind: .primaryText, text: "Seconda parte", sequence: 2),
            ],
            isStreaming: true
        )

        let events = [
            makeEvent(sequence: 3, title: "Read file", tool: "read", path: "/tmp/A.swift"),
        ]

        let synthetic = SyntheticChatTurnStateFromTraceEvents.makeForMergeIfNeeded(
            base: base,
            conversationId: conversationId,
            traceEvents: events
        )

        guard let synthetic else {
            XCTFail("Expected synthetic timeline state")
            return
        }

        let blocks = synthetic.blocks
        XCTAssertEqual(blocks.map(\.kind), [.primaryText, .primaryText, .toolMarker])
        XCTAssertEqual(blocks.map(\.sequence), [0, 2, 3])
        XCTAssertEqual(
            blocks.filter { $0.kind == .primaryText }.compactMap(\.text),
            ["Prima parte", "Seconda parte"]
        )
    }

    func testSyntheticFallbackInterleavesToolMarkersBetweenPrimaryBlocks() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let base = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "Prima parte\n\nSeconda parte",
            primaryTextSnapshot: "Prima parte\n\nSeconda parte",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
                makeBlock(id: "text-1", kind: .primaryText, text: "Seconda parte", sequence: 2),
            ],
            isStreaming: true
        )

        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
        ]

        let synthetic = SyntheticChatTurnStateFromTraceEvents.makeForMergeIfNeeded(
            base: base,
            conversationId: conversationId,
            traceEvents: events
        )

        guard let synthetic else {
            XCTFail("Expected synthetic timeline state")
            return
        }

        let blocks = synthetic.blocks
        XCTAssertEqual(blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])
        XCTAssertEqual(blocks.map(\.sequence), [0, 1, 2])
    }

    func testSyntheticFallbackPreservesThreePrimaryNarrativeBlocksAroundMultipleMarkers() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let base = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "Uno\n\nDue\n\nTre",
            primaryTextSnapshot: "Uno\n\nDue\n\nTre",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "Uno", sequence: 0),
                makeBlock(id: "text-1", kind: .primaryText, text: "Due", sequence: 3),
                makeBlock(id: "text-2", kind: .primaryText, text: "Tre", sequence: 6),
            ],
            isStreaming: true
        )
        let events = [
            makeEvent(sequence: 1, title: "Read A", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 4, title: "Read B", tool: "read", path: "/tmp/B.swift"),
        ]

        let synthetic = SyntheticChatTurnStateFromTraceEvents.makeForMergeIfNeeded(
            base: base,
            conversationId: conversationId,
            traceEvents: events
        )

        guard let synthetic else {
            XCTFail("Expected synthetic timeline state")
            return
        }

        XCTAssertEqual(
            synthetic.blocks.map(\.sequence),
            [0, 1, 3, 4, 6]
        )
        XCTAssertEqual(
            synthetic.blocks.map(\.kind),
            [.primaryText, .toolMarker, .primaryText, .toolMarker, .primaryText]
        )
    }

    func testSyntheticFallbackAvoidsMonolithWhenToolMarkersLandBetweenFourNarrativeBlocks() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let base = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "A\n\nB\n\nC\n\nD",
            primaryTextSnapshot: "A\n\nB\n\nC\n\nD",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "A", sequence: 0),
                makeBlock(id: "text-1", kind: .primaryText, text: "B", sequence: 2),
                makeBlock(id: "text-2", kind: .primaryText, text: "C", sequence: 5),
                makeBlock(id: "text-3", kind: .primaryText, text: "D", sequence: 7),
            ],
            isStreaming: true
        )
        let events = [
            makeEvent(sequence: 1, title: "Read A", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 6, title: "Read C", tool: "read", path: "/tmp/C.swift"),
        ]

        let synthetic = SyntheticChatTurnStateFromTraceEvents.makeForMergeIfNeeded(
            base: base,
            conversationId: conversationId,
            traceEvents: events
        )

        guard let synthetic else {
            XCTFail("Expected synthetic timeline state")
            return
        }

        XCTAssertEqual(
            synthetic.blocks.filter { $0.kind == .primaryText }.map(\.text),
            ["A", "B", "C", "D"]
        )
        XCTAssertEqual(
            synthetic.blocks.map(\.sequence),
            [0, 1, 2, 5, 6, 7]
        )
    }
}
