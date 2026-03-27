import XCTest
@testable import CoderIDE

final class TodoChatDisplayScopeSnapshotTests: XCTestCase {
    func testSnapshotBasedPolicyMatchesLegacyVisibleTodosPolicy() {
        let convA = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let convB = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let visible = [
            TodoItem(title: "Manual", source: .manual),
            TodoItem(title: "Orphan", source: .agent, planConversationId: nil),
            TodoItem(title: "Scoped A", source: .agent, planConversationId: convA),
            TodoItem(title: "Scoped B", source: .agent, planConversationId: convB),
        ]
        let snapshot = TodoChatDisplayScopeSnapshot(visibleTodos: visible)

        for conversationId in [convA, convB] {
            let legacyIds = Set(
                visible
                    .filter {
                        TodoChatDisplayPolicy.itemAppearsInChat(
                            $0,
                            conversationId: conversationId,
                            visibleTodos: visible
                        )
                    }
                    .map(\.id)
            )
            let snapshotIds = Set(
                visible
                    .filter {
                        TodoChatDisplayPolicy.itemAppearsInChat(
                            $0,
                            conversationId: conversationId,
                            scopeSnapshot: snapshot
                        )
                    }
                    .map(\.id)
            )
            XCTAssertEqual(snapshotIds, legacyIds)
        }
    }
}
