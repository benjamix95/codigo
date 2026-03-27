import Combine
import XCTest
@testable import CoderIDE

@MainActor
final class RustMainChatStoreAdapterScopedApplyTests: XCTestCase {
    func testScopedSnapshotIncludesOnlyRequestedConversationAndPlanBoard() throws {
        let suiteName = "RustMainChatStoreAdapterScopedApplyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatStore(userDefaults: defaults)
        let firstConversationId = try XCTUnwrap(store.conversations.first?.id)
        let secondConversationId = store.createConversation(contextId: nil, contextFolderPath: nil, mode: .agent)

        store.planBoards = [
            firstConversationId: PlanBoard(
                goal: "First board",
                options: [PlanOption(id: 1, title: "One", fullText: "Do one thing")],
                chosenPath: nil,
                steps: [
                    PlanStep(
                        id: "1",
                        title: "Step",
                        description: "Step",
                        targetFile: nil,
                        status: .pending
                    ),
                ],
                updatedAt: .now
            ),
        ]

        let snapshot = RustMainChatStoreAdapter.scopedSnapshot(
            from: store,
            conversationIds: Set([secondConversationId]),
            planBoardConversationIds: Set([firstConversationId])
        )

        XCTAssertEqual(snapshot.conversations.count, 1)
        XCTAssertEqual(
            UUID(uuidString: try XCTUnwrap(snapshot.conversations.first?.id)),
            secondConversationId
        )
        XCTAssertEqual(snapshot.planBoards.count, 1)
        XCTAssertNotNil(snapshot.planBoards[firstConversationId.lowercasedString])
        XCTAssertNil(snapshot.planBoards[secondConversationId.lowercasedString])
    }

    func testApplyScopedForPipelinePublishesWhenReplacingExistingConversationWithSameMessageCount() throws {
        let suiteName = "RustMainChatStoreAdapterScopedApplyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatStore(userDefaults: defaults)
        let conversationId = try XCTUnwrap(store.conversations.first?.id)
        store.addMessage(
            ChatMessage(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                role: .assistant,
                content: "before",
                isStreaming: true
            ),
            to: conversationId
        )

        var publishCount = 0
        let published = expectation(description: "scoped apply publishes chat invalidation")
        published.assertForOverFulfill = false
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
            published.fulfill()
        }
        defer { cancellable.cancel() }

        let snapshot = RustMainChatStoreAdapter.snapshot(from: store)
        let conversation = try XCTUnwrap(snapshot.conversations.first(where: {
            UUID(uuidString: $0.id) == conversationId
        }))
        let updatedConversation = MainChatStoreConversationSnapshotBridge(
            id: conversation.id,
            threadRootConversationId: conversation.threadRootConversationId,
            title: conversation.title,
            messages: [
            RustMainChatStoreAdapter.messageSnapshot(
                ChatMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                    role: .assistant,
                    content: "after",
                    isStreaming: true
                )
                )
            ],
            createdAt: conversation.createdAt,
            contextId: conversation.contextId,
            contextFolderPath: conversation.contextFolderPath,
            mode: conversation.mode,
            preferredProviderId: conversation.preferredProviderId,
            contextMemorySummaryMarkdown: conversation.contextMemorySummaryMarkdown,
            contextMemoryGeneratedAt: conversation.contextMemoryGeneratedAt,
            contextMemorySourceMessageCount: conversation.contextMemorySourceMessageCount,
            isArchived: conversation.isArchived,
            isPinned: conversation.isPinned,
            isFavorite: conversation.isFavorite,
            lastInputTokens: conversation.lastInputTokens,
            workspaceId: conversation.workspaceId,
            adHocFolderPaths: conversation.adHocFolderPaths,
            checkpoints: conversation.checkpoints
        )
        let index = try XCTUnwrap(snapshot.conversations.firstIndex(where: {
            UUID(uuidString: $0.id) == conversationId
        }))
        var conversations = snapshot.conversations
        conversations[index] = updatedConversation
        let updatedSnapshot = MainChatStoreSnapshotBridge(
            conversations: conversations,
            planBoards: snapshot.planBoards
        )

        RustMainChatStoreAdapter.applyScopedForPipeline(
            snapshot: updatedSnapshot,
            to: store,
            conversationId: conversationId
        )

        wait(for: [published], timeout: 0.05)
        XCTAssertGreaterThanOrEqual(publishCount, 1)
        XCTAssertEqual(
            store.conversation(for: conversationId)?.messages.last?.content,
            "after"
        )
    }
}
