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

    func testInterleaverKeepsDistinctCategoriesSeparated() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "command_execution", type: "command_execution", command: "swift test"),
            makeEvent(sequence: 3, title: "Write patch", tool: "write", path: "/tmp/B.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let toolSegments = segments.compactMap { segment -> ToolTraceEvent? in
            if case .toolEvent(_, let event, _) = segment { return event }
            return nil
        }

        XCTAssertEqual(toolSegments.map(\.title), ["Read file", "command_execution", "Write patch"])
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2, 3, 4])
    }

    func testInterleaverGroupsConsecutiveExplorationEvents() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/ChatTurnView.swift"),
            makeEvent(sequence: 2, title: "read", tool: "read", path: "/tmp/MessageToolTraceView.swift"),
            makeEvent(sequence: 3, title: "grep", tool: "grep", query: "ToolTraceEvent"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groups = segments.compactMap { segment -> ChatTurnToolEventGroup? in
            if case .toolGroup(_, let group, _) = segment { return group }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].category, .exploration)
        XCTAssertEqual(groups[0].events.count, 3)
        XCTAssertEqual(segments.map(\.sequence), [0, 1, 4])
    }

    func testInterleaverDoesNotGroupAcrossNarrativeBoundary() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Middle", sequence: 2),
            PersistedChatTimelineBlock(id: "text-2", kind: .primaryText, text: "Bye", sequence: 4),
        ]
        let events = [
            makeEvent(sequence: 1, title: "read", tool: "read", path: "/tmp/ChatTurnView.swift"),
            makeEvent(sequence: 3, title: "read", tool: "read", path: "/tmp/ChatTurnInterleavedSegment.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groupCount = segments.filter {
            if case .toolGroup = $0 { return true }
            return false
        }.count
        let eventCount = segments.filter {
            if case .toolEvent = $0 { return true }
            return false
        }.count

        XCTAssertEqual(groupCount, 0)
        XCTAssertEqual(eventCount, 2)
    }

    func testInterleaverGroupsConsecutiveTerminalEvents() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Hi", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Bye", sequence: 3),
        ]
        let events = [
            makeEvent(sequence: 1, title: "command_execution", type: "command_execution", command: "xcodebuild test"),
            makeEvent(sequence: 2, title: "command_execution", type: "command_execution", command: "swift test"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)
        let groups = segments.compactMap { segment -> ChatTurnToolEventGroup? in
            if case .toolGroup(_, let group, _) = segment { return group }
            return nil
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].category, .terminal)
        XCTAssertEqual(groups[0].events.count, 2)
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

    func testInterleaverReasoningBeforeTextWhenSequenceEqualRegardlessOfId() {
        let blocks = [
            PersistedChatTimelineBlock(id: "aaaa-text", kind: .primaryText, text: "Answer", sequence: 0),
            PersistedChatTimelineBlock(id: "zzzz-reason", kind: .reasoning, text: "Think", sequence: 0),
        ]
        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: [])
        XCTAssertEqual(segments.count, 2)
        if case .reasoning(let id, let text, let seq) = segments[0] {
            XCTAssertEqual(seq, 0)
            XCTAssertEqual(id, "zzzz-reason")
            XCTAssertEqual(text, "Think")
        } else {
            XCTFail("Con sequence uguale il reasoning deve precedere il testo (tie-break stabile)")
        }
        if case .text(let id, _, let seq) = segments[1] {
            XCTAssertEqual(seq, 0)
            XCTAssertEqual(id, "aaaa-text")
        } else {
            XCTFail("Secondo segmento atteso: testo")
        }
    }

    func testInterleaverKeepsSinglePrimaryBeforeToolsWhenNoToolMarkers() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Riepilogo", sequence: 0),
        ]
        let events = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "Write patch", tool: "write", path: "/tmp/B.swift"),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(blocks: blocks, traceEvents: events)

        XCTAssertEqual(
            segments.map(\.sequence),
            [0, 1, 2],
            "Con un solo primaryText a sequence 0 e trace senza toolMarker, il testo non va dopo tutti i tool."
        )
        if case .text(_, let content, let seq) = segments[0] {
            XCTAssertEqual(seq, 0)
            XCTAssertEqual(content, "Riepilogo")
        } else {
            XCTFail("Atteso segmento .text come primo")
        }
    }

    func testInterleaverMovesTrailingSubagentSnapshotsBeforeFinalText() {
        let blocks = [
            PersistedChatTimelineBlock(id: "text-0", kind: .primaryText, text: "Analisi", sequence: 0),
            PersistedChatTimelineBlock(id: "text-1", kind: .primaryText, text: "Risposta finale", sequence: 2),
        ]
        let snapshots = [
            SubagentCardSnapshot(
                swarmId: "sa-review",
                status: .completed,
                title: "Reviewer",
                detail: "done",
                summary: "ok",
                errorCount: 0,
                warningCount: 0,
                resultPreview: "done",
                transcript: nil
            ),
        ]

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: blocks,
            traceEvents: [],
            subagentSnapshots: snapshots
        )

        let finalTextIndex = try! XCTUnwrap(segments.lastIndex(where: { segment in
            if case .text(_, let content, _) = segment {
                return content == "Risposta finale"
            }
            return false
        }))
        let snapshotIndex = try! XCTUnwrap(segments.firstIndex(where: { segment in
            if case .subagentSnapshot(_, let snapshot, _) = segment {
                return snapshot.swarmId == "sa-review"
            }
            return false
        }))

        XCTAssertLessThan(snapshotIndex, finalTextIndex)
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
                PersistedChatTimelineBlock(
                    id: "text-0",
                    kind: .primaryText,
                    text: "Prima parte",
                    sequence: 0
                ),
                PersistedChatTimelineBlock(
                    id: "text-1",
                    kind: .primaryText,
                    text: "Seconda parte",
                    sequence: 2
                ),
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
                PersistedChatTimelineBlock(
                    id: "text-0",
                    kind: .primaryText,
                    text: "Prima parte",
                    sequence: 0
                ),
                PersistedChatTimelineBlock(
                    id: "text-1",
                    kind: .primaryText,
                    text: "Seconda parte",
                    sequence: 2
                ),
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
        XCTAssertEqual(
            blocks.filter { $0.kind == .primaryText }.compactMap(\.text),
            ["Prima parte", "Seconda parte"]
        )
    }

    private func makeEvent(
        sequence: Int,
        title: String,
        type: String = "mcp_tool_call",
        tool: String = "read",
        path: String? = nil,
        query: String? = nil,
        command: String? = nil,
        swarmId: String? = nil
    ) -> ToolTraceEvent {
        var payload = ["mcp_tool": tool]
        if let path {
            payload["path"] = path
        }
        if let query {
            payload["query"] = query
        }
        if let command {
            payload["command"] = command
        }
        if let swarmId {
            payload["swarm_id"] = swarmId
        }
        return ToolTraceEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            providerId: "codex-cli",
            conversationId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            assistantMessageId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            type: type,
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
