import XCTest
@testable import CoderIDE

final class ChatStreamingTimelineTurnResolverTests: ChatTimelineInterleavingTestCase {
    func testRestoredTurnStateFromPersistedAssistantMessagePreservesInterleavedTimeline() {
        let conversationId = UUID()
        let assistantId = UUID()
        let message = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Prima parteSeconda parte",
            primaryTextSnapshot: "Prima parteSeconda parte",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
                makeBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
                makeBlock(id: "text-1", kind: .primaryText, text: "Seconda parte", sequence: 2),
            ],
            isStreaming: true
        )

        let restored = restoredChatTurnStateFromPersistedAssistantMessage(
            conversationId: conversationId,
            message: message
        )

        XCTAssertEqual(restored.timelineSegments.map(\.kind), [.text, .toolUse, .text])
        XCTAssertEqual(restored.textSegments, ["Prima parte", "Seconda parte"])
        XCTAssertEqual(restored.blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])
        XCTAssertEqual(restored.blocks.map(\.sequence), [0, 1, 2])
    }

    func testResolverUsesPersistedMessageBeforeSyntheticFallbackWhenStoreHasRicherBlocks() {
        let conversationId = UUID()
        let assistantId = UUID()
        let base = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Prima parteSeconda parte",
            primaryTextSnapshot: "Prima parteSeconda parte",
            blocks: [
                makeBlock(id: "primary-text", kind: .primaryText, text: "Prima parteSeconda parte", sequence: 0),
            ],
            isStreaming: true
        )
        let persisted = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Prima parteSeconda parte",
            primaryTextSnapshot: "Prima parteSeconda parte",
            blocks: [
                makeBlock(id: "text-0", kind: .primaryText, text: "Prima parte", sequence: 0),
                makeBlock(id: "tool-marker-1", kind: .toolMarker, sequence: 1),
                makeBlock(id: "text-1", kind: .primaryText, text: "Seconda parte", sequence: 2),
            ],
            isStreaming: true
        )
        let traceEvents = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
        ]

        let resolution = ChatStreamingTimelineTurnResolver.resolve(
            base: base,
            conversationId: conversationId,
            integrationTurn: nil,
            conversationTurn: nil,
            cachedAssistantTurn: nil,
            persistedMessage: persisted,
            traceEvents: traceEvents
        )

        XCTAssertEqual(resolution.source, .persistedMessage)
        XCTAssertFalse(resolution.usedSynthetic)
        XCTAssertEqual(resolution.turn?.blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])

        let segments = ChatTurnTimelineInterleaver.segments(
            blocks: resolution.turn?.blocks ?? [],
            traceEvents: traceEvents
        )

        XCTAssertEqual(segments.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(
            segments.map {
                switch $0 {
                case .text: return "text"
                case .toolEvent: return "tool"
                default: return "other"
                }
            },
            ["text", "tool", "text"]
        )
    }

    func testResolverPrefersAssistantSpecificCacheOverDifferentConversationTurn() {
        let conversationId = UUID()
        let assistantId = UUID()
        let otherAssistantId = UUID()
        let base = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Prima parteSeconda parte",
            primaryTextSnapshot: "Prima parteSeconda parte",
            blocks: [
                makeBlock(id: "primary-text", kind: .primaryText, text: "Prima parteSeconda parte", sequence: 0),
            ],
            isStreaming: false
        )

        var cached = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        cached.textSegments = ["Prima parte", "Seconda parte"]
        cached.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        cached.timelineNextSequence = 3

        var conversationTurn = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: otherAssistantId,
            turnId: otherAssistantId.uuidString,
            providerId: "codex-cli"
        )
        conversationTurn.textSegments = ["Altro turno"]
        conversationTurn.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
        ]
        conversationTurn.timelineNextSequence = 1

        let resolution = ChatStreamingTimelineTurnResolver.resolve(
            base: base,
            conversationId: conversationId,
            integrationTurn: nil,
            conversationTurn: conversationTurn,
            cachedAssistantTurn: cached,
            persistedMessage: nil,
            traceEvents: []
        )

        XCTAssertEqual(resolution.source, .assistantMessageCache)
        XCTAssertEqual(resolution.turn?.assistantMessageId, assistantId)
        XCTAssertEqual(resolution.turn?.blocks.map(\.kind), [.primaryText, .toolMarker, .primaryText])
    }

    func testResolverKeepsSyntheticFallbackWhenNoRealTurnExists() {
        let conversationId = UUID()
        let assistantId = UUID()
        let base = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "Risposta monolitica",
            primaryTextSnapshot: "Risposta monolitica",
            blocks: [
                makeBlock(id: "primary-text", kind: .primaryText, text: "Risposta monolitica", sequence: 0),
            ],
            isStreaming: true
        )
        let traceEvents = [
            makeEvent(sequence: 1, title: "Read file", tool: "read", path: "/tmp/A.swift"),
            makeEvent(sequence: 2, title: "Read file", tool: "read", path: "/tmp/B.swift"),
        ]

        let resolution = ChatStreamingTimelineTurnResolver.resolve(
            base: base,
            conversationId: conversationId,
            integrationTurn: nil,
            conversationTurn: nil,
            cachedAssistantTurn: nil,
            persistedMessage: nil,
            traceEvents: traceEvents
        )

        XCTAssertEqual(resolution.source, .synthetic)
        XCTAssertTrue(resolution.usedSynthetic)
        XCTAssertEqual(resolution.syntheticReason, "no_pipeline_turn")
        XCTAssertEqual(
            resolution.turn?.blocks.filter { $0.kind == .toolMarker }.count,
            2
        )
    }
}
