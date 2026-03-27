import XCTest
@testable import CoderIDE

@MainActor
final class SidebarThreadSnapshotTests: XCTestCase {
    func testBuildFiltersAndOrdersThreadsForActiveContext() {
        let defaults = UserDefaults(suiteName: #filePath + ".\(UUID().uuidString)") ?? .standard
        let chatStore = ChatStore(userDefaults: defaults)
        let contextId = UUID()
        let otherContextId = UUID()
        let now = Date()

        chatStore.conversations = [
            Conversation(
                title: "Pinned Thread",
                createdAt: now.addingTimeInterval(-30),
                contextId: contextId,
                isPinned: true
            ),
            Conversation(
                title: "Favorite Thread",
                createdAt: now.addingTimeInterval(-60),
                contextId: contextId,
                isFavorite: true
            ),
            Conversation(
                title: "Archived Thread",
                createdAt: now.addingTimeInterval(-10),
                contextId: contextId,
                isArchived: true
            ),
            Conversation(
                title: "Different Context",
                createdAt: now,
                contextId: otherContextId
            ),
            Conversation(
                title: "Global Thread",
                createdAt: now,
                contextId: nil
            )
        ]

        let snapshot = SidebarThreadSnapshotBuilder.build(
            chatStore: chatStore,
            contextId: contextId,
            query: "",
            showArchived: false,
            favoritesOnly: false
        )

        XCTAssertEqual(snapshot.threads.map(\.title), ["Pinned Thread", "Favorite Thread"])
        XCTAssertEqual(snapshot.pinnedThreads.map(\.title), ["Pinned Thread"])
        XCTAssertEqual(snapshot.dateBuckets.flatMap(\.threads).map(\.title), ["Favorite Thread"])
    }

    func testBuildRenderStatesPrecomputesDraftTaskAndTodoMetadata() throws {
        let defaults = UserDefaults(suiteName: #filePath + ".\(UUID().uuidString)") ?? .standard
        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "SidebarThreadSnapshotTests.todos",
            userDefaults: defaults
        )
        let toolTraceStore = ToolTraceStore()
        let conversationId = UUID()

        chatStore.conversations = [
            Conversation(
                id: conversationId,
                title: "Working Thread",
                messages: [
                    ChatMessage(role: .user, content: "Hello"),
                    ChatMessage(role: .assistant, content: "Streaming", isStreaming: true),
                ]
            )
        ]
        chatStore.draftTexts[conversationId] = "pending draft"
        chatStore.activeTaskConversationIds = [conversationId]
        chatStore.taskStatusTexts[conversationId] = "Running"
        todoStore.todos = [
            TodoItem(
                title: "First",
                status: .inProgress,
                source: .agent,
                planConversationId: conversationId
            ),
            TodoItem(
                title: "Second",
                status: .pending,
                source: .agent,
                planConversationId: conversationId
            ),
        ]

        let renderStates = SidebarThreadSnapshotBuilder.buildRenderStates(
            conversations: chatStore.conversations,
            chatStore: chatStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        )

        let renderState = try XCTUnwrap(renderStates[conversationId])
        XCTAssertTrue(renderState.hasDraft)
        XCTAssertTrue(renderState.isActive)
        XCTAssertTrue(renderState.isStreaming)
        XCTAssertEqual(renderState.statusText, "Running")
        XCTAssertEqual(renderState.todoProgressLabel, "1/2")
        XCTAssertFalse(renderState.metrics.hasDiffStats)
    }

    func testSnapshotFingerprintIgnoresMessageContentOnlyMutations() {
        let defaults = UserDefaults(suiteName: #filePath + ".\(UUID().uuidString)") ?? .standard
        let chatStore = ChatStore(userDefaults: defaults)
        let contextId = UUID()
        let conversationId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_710_000_000)

        chatStore.conversations = [
            Conversation(
                id: conversationId,
                title: "Stable Thread",
                messages: [ChatMessage(role: .assistant, content: "alpha")],
                createdAt: createdAt,
                contextId: contextId
            )
        ]

        let before = SidebarThreadSnapshotBuilder.snapshotFingerprint(
            chatStore: chatStore,
            contextId: contextId,
            query: "",
            showArchived: false,
            favoritesOnly: false
        )

        chatStore.conversations = [
            Conversation(
                id: conversationId,
                title: "Stable Thread",
                messages: [ChatMessage(role: .assistant, content: "alpha beta gamma")],
                createdAt: createdAt,
                contextId: contextId
            )
        ]

        let after = SidebarThreadSnapshotBuilder.snapshotFingerprint(
            chatStore: chatStore,
            contextId: contextId,
            query: "",
            showArchived: false,
            favoritesOnly: false
        )

        XCTAssertEqual(before, after)
    }

    func testRenderFingerprintChangesOnlyWhenVisibleThreadStateChanges() {
        let defaults = UserDefaults(suiteName: #filePath + ".\(UUID().uuidString)") ?? .standard
        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "SidebarThreadSnapshotTests.render.todos",
            userDefaults: defaults
        )
        let toolTraceStore = ToolTraceStore()
        let conversationId = UUID()

        chatStore.conversations = [
            Conversation(
                id: conversationId,
                title: "Visible Thread",
                messages: [ChatMessage(role: .assistant, content: "stream-a", isStreaming: true)]
            )
        ]
        chatStore.activeTaskConversationIds = [conversationId]

        let before = SidebarThreadSnapshotBuilder.renderFingerprint(
            conversations: chatStore.conversations,
            chatStore: chatStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        )

        chatStore.conversations = [
            Conversation(
                id: conversationId,
                title: "Visible Thread",
                messages: [ChatMessage(role: .assistant, content: "stream-b stream-c", isStreaming: true)]
            )
        ]

        let sameState = SidebarThreadSnapshotBuilder.renderFingerprint(
            conversations: chatStore.conversations,
            chatStore: chatStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        )

        chatStore.taskStatusTexts[conversationId] = "Running"
        let changedState = SidebarThreadSnapshotBuilder.renderFingerprint(
            conversations: chatStore.conversations,
            chatStore: chatStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        )

        XCTAssertEqual(before, sameState)
        XCTAssertNotEqual(before, changedState)
    }
}
