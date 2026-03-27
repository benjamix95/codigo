import XCTest
@testable import CoderIDE

@MainActor
final class RustMainChatScopedStoreActionTests: XCTestCase {
    func testScopedSnapshotForAppendMessageIncludesOnlyTargetConversation() throws {
        let suiteName = "RustMainChatScopedStoreActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatStore(userDefaults: defaults)
        _ = try XCTUnwrap(store.conversations.first?.id)
        let secondConversationId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: .agent)

        var request = MainChatStoreActionRequestBridge(
            schemaVersion: 1,
            action: "append_message",
            snapshot: MainChatStoreSnapshotBridge(conversations: [], planBoards: [:]),
            conversationId: secondConversationId.uuidString.lowercased(),
            messageId: nil,
            checkpointId: nil,
            messageCount: nil,
            conversation: nil,
            message: RustMainChatStoreAdapter.messageSnapshot(ChatMessage(role: .assistant, content: "hello")),
            planBoard: nil,
            checkpoint: nil,
            title: nil,
            mode: nil,
            providerId: nil,
            contextId: nil,
            contextFolderPath: nil,
            workspaceId: nil,
            boolValue: nil,
            intValue: nil,
            text: nil,
            stringList: [],
            subagentCards: nil
        )

        let scope = try XCTUnwrap(store.rustStoreActionScope(for: request))
        request.snapshot = store.scopedRustStoreSnapshot(for: request, scope: scope)

        XCTAssertEqual(request.snapshot.conversations.count, 1)
        XCTAssertEqual(
            UUID(uuidString: try XCTUnwrap(request.snapshot.conversations.first?.id)),
            secondConversationId
        )
    }
}
