import XCTest
@testable import CoderIDE

final class MainChatUIIntentRuntimeSyncTests: XCTestCase {
    func testMainChatUIIntentRuntimeTurnStateExtractsMatchingConversationTurn() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        var turnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            providerId: "codex-cli"
        )
        turnState.textSegments = ["Prima parte", "Seconda parte"]
        turnState.timelineSegments = [
            ChatTimelineSegment(kind: .text, index: 0, sequence: 0),
            ChatTimelineSegment(kind: .toolUse, index: 0, sequence: 1),
            ChatTimelineSegment(kind: .text, index: 1, sequence: 2),
        ]
        turnState.timelineNextSequence = 3

        let response = MainChatUIIntentResponseBridge(
            schemaVersion: 1,
            error: nil,
            state: MainChatUIStateBridge(
                storeSnapshot: MainChatStoreSnapshotBridge(conversations: [], planBoards: [:]),
                runtimeSnapshot: MainChatRuntimeSnapshotBridge(
                    turnState: MainChatBridgeState(turnState),
                    mode: .agent,
                    directStream: nil,
                    plan: nil,
                    output: nil
                ),
                taskRuntimeState: nil,
                selectedConversationId: conversationId.uuidString.lowercased(),
                draftText: "",
                planPanelVisible: false,
                followLive: true,
                collapsedArtifactIdsByTurn: [:],
                autoTodoRuntimeStateByMessage: [:]
            ),
            snapshot: nil,
            todoPatches: []
        )

        let extracted = mainChatUIIntentRuntimeTurnState(
            response: response,
            targetConversationId: conversationId
        )

        XCTAssertEqual(extracted?.conversationId, conversationId)
        XCTAssertEqual(extracted?.timelineSegments.map(\.kind), [.text, .toolUse, .text])
        XCTAssertEqual(extracted?.textSegments, ["Prima parte", "Seconda parte"])
    }

    func testMainChatUIIntentRuntimeTurnStateIgnoresMismatchedConversation() {
        let response = MainChatUIIntentResponseBridge(
            schemaVersion: 1,
            error: nil,
            state: MainChatUIStateBridge(
                storeSnapshot: MainChatStoreSnapshotBridge(conversations: [], planBoards: [:]),
                runtimeSnapshot: MainChatRuntimeSnapshotBridge(
                    turnState: MainChatBridgeState(
                        ChatTurnState(
                            conversationId: UUID(),
                            assistantMessageId: UUID(),
                            turnId: UUID().uuidString,
                            providerId: "codex-cli"
                        )
                    ),
                    mode: .agent,
                    directStream: nil,
                    plan: nil,
                    output: nil
                ),
                taskRuntimeState: nil,
                selectedConversationId: nil,
                draftText: "",
                planPanelVisible: false,
                followLive: true,
                collapsedArtifactIdsByTurn: [:],
                autoTodoRuntimeStateByMessage: [:]
            ),
            snapshot: nil,
            todoPatches: []
        )

        XCTAssertNil(
            mainChatUIIntentRuntimeTurnState(
                response: response,
                targetConversationId: UUID()
            )
        )
    }
}
