import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreForkTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let planKey = "CoderIDE.planBoards"

    override func setUp() {
        super.setUp()
        clearPersistedState()
    }

    override func tearDown() {
        clearPersistedState()
        super.tearDown()
    }

    func testForkClonesMessagesAndRequiredMetadata() throws {
        let store = ChatStore()
        let sourceId = try XCTUnwrap(store.conversations.first?.id)

        let sourceMessages: [ChatMessage] = [
            ChatMessage(
                role: .user,
                content: "Ship this",
                isStreaming: false
            ),
            ChatMessage(
                role: .assistant,
                content: "Done",
                isStreaming: false,
                attachments: [
                    ChatAttachment(
                        kind: .document,
                        originalName: "report.pdf",
                        localPath: "/tmp/report.pdf"
                    ),
                ],
                planAttachment: PlanAttachment(
                    historyEntryId: UUID(),
                    layoutVersion: 1,
                    showExpand: true,
                    snapshotTitle: "Plan snapshot"
                )
            ),
        ]

        store.conversations[0] = Conversation(
            id: sourceId,
            title: "Release Checklist",
            messages: sourceMessages,
            createdAt: .distantPast,
            contextId: UUID(),
            contextFolderPath: "/repo",
            mode: .agent,
            preferredProviderId: "codex-cli",
            isArchived: true,
            isPinned: true,
            isFavorite: true,
            workspaceId: UUID(),
            adHocFolderPaths: ["/repo"],
            checkpoints: [
                ConversationCheckpoint(messageCount: 1, planBoardSnapshot: nil, gitStates: []),
            ]
        )

        let forkId = try XCTUnwrap(store.forkConversation(from: sourceId))
        let fork = try XCTUnwrap(store.conversation(for: forkId))
        let source = try XCTUnwrap(store.conversation(for: sourceId))

        XCTAssertEqual(fork.contextId, source.contextId)
        XCTAssertEqual(fork.contextFolderPath, source.contextFolderPath)
        XCTAssertEqual(fork.mode, source.mode)
        XCTAssertEqual(fork.preferredProviderId, source.preferredProviderId)

        XCTAssertFalse(fork.isArchived)
        XCTAssertFalse(fork.isPinned)
        XCTAssertFalse(fork.isFavorite)
        XCTAssertTrue(fork.checkpoints.isEmpty)

        XCTAssertEqual(fork.messages.count, source.messages.count)
        XCTAssertNotEqual(fork.messages[0].id, source.messages[0].id)
        XCTAssertNotEqual(fork.messages[1].id, source.messages[1].id)
        XCTAssertNil(fork.messages[1].planAttachment)
        XCTAssertFalse(fork.messages[1].isStreaming)
    }

    func testForkReturnsNewIdAndTitleSuffix() throws {
        let store = ChatStore()
        let sourceId = try XCTUnwrap(store.conversations.first?.id)
        store.setTitle(conversationId: sourceId, title: "My Thread")

        let forkId = try XCTUnwrap(store.forkConversation(from: sourceId))
        XCTAssertNotEqual(forkId, sourceId)
        XCTAssertEqual(store.conversation(for: forkId)?.title, "My Thread (Fork)")
    }

    func testForkMessagesDivergeFromSourceAfterEdits() throws {
        let store = ChatStore()
        let sourceId = try XCTUnwrap(store.conversations.first?.id)
        store.conversations[0] = Conversation(
            id: sourceId,
            title: "Thread",
            messages: [ChatMessage(role: .assistant, content: "Origin", isStreaming: false)]
        )

        let forkId = try XCTUnwrap(store.forkConversation(from: sourceId))
        store.addMessage(ChatMessage(role: .user, content: "Fork only", isStreaming: false), to: forkId)

        let source = try XCTUnwrap(store.conversation(for: sourceId))
        let fork = try XCTUnwrap(store.conversation(for: forkId))
        XCTAssertEqual(source.messages.count, 1)
        XCTAssertEqual(fork.messages.count, 2)
        XCTAssertEqual(source.messages.last?.content, "Origin")
        XCTAssertEqual(fork.messages.last?.content, "Fork only")
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
