import XCTest
@testable import CoderIDE

final class MainChatRuntimeSnapshotPreferenceTests: XCTestCase {
    func testShouldPreferConversationRuntimeTurnStateWhenItHasMoreToolMarkers() {
        let conversationId = UUID()
        let assistantId = UUID()

        var baseTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        baseTurnState.textSegments = ["Prima parte"]
        baseTurnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
        ]
        baseTurnState.timelineNextSequence = 1

        var conversationTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        conversationTurnState.textSegments = ["Prima parte", "Seconda parte"]
        conversationTurnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        conversationTurnState.timelineNextSequence = 3

        XCTAssertTrue(
            shouldPreferConversationRuntimeTurnState(
                baseTurnState: baseTurnState,
                conversationTurnState: conversationTurnState,
                conversationId: conversationId
            )
        )
    }

    func testPreferredConversationRuntimeSnapshotReplacesExplicitSnapshotWhenConversationRuntimeIsRicher() {
        let conversationId = UUID()
        let assistantId = UUID()

        var baseTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        baseTurnState.textSegments = ["Monolithic"]
        baseTurnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
        ]
        baseTurnState.timelineNextSequence = 1

        var conversationTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        conversationTurnState.textSegments = ["Prima parte", "Seconda parte"]
        conversationTurnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        conversationTurnState.timelineNextSequence = 3

        let baseSnapshot = MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(baseTurnState),
            mode: .plan,
            directStream: nil,
            plan: nil,
            output: nil
        )

        let preferred = preferredConversationRuntimeSnapshot(
            baseSnapshot: baseSnapshot,
            conversationTurnState: conversationTurnState,
            conversationId: conversationId
        )

        XCTAssertEqual(preferred?.mode, .plan)
        XCTAssertEqual(preferred?.turnState.chatTurnState, conversationTurnState)
    }

    func testShouldNotPreferConversationRuntimeTurnStateForDifferentConversation() {
        XCTAssertFalse(
            shouldPreferConversationRuntimeTurnState(
                baseTurnState: ChatTurnState(
                    conversationId: UUID(),
                    assistantMessageId: UUID(),
                    turnId: UUID().uuidString,
                    providerId: "codex-cli"
                ),
                conversationTurnState: ChatTurnState(
                    conversationId: UUID(),
                    assistantMessageId: UUID(),
                    turnId: UUID().uuidString,
                    providerId: "codex-cli"
                ),
                conversationId: UUID()
            )
        )
    }

    func testPreferredConversationRuntimeSnapshotCreatesAgentSnapshotWhenBaseIsMissing() {
        let conversationId = UUID()
        let assistantId = UUID()

        var conversationTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantId,
            turnId: assistantId.uuidString,
            providerId: "codex-cli"
        )
        conversationTurnState.textSegments = ["Prima parte", "Seconda parte"]
        conversationTurnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        conversationTurnState.timelineNextSequence = 3

        let preferred = preferredConversationRuntimeSnapshot(
            baseSnapshot: nil,
            conversationTurnState: conversationTurnState,
            conversationId: conversationId
        )

        XCTAssertEqual(preferred?.mode, .agent)
        XCTAssertEqual(preferred?.turnState.chatTurnState, conversationTurnState)
    }
}
