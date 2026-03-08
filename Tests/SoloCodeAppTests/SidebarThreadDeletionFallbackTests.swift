import XCTest
@testable import CoderIDE

final class SidebarThreadDeletionFallbackTests: XCTestCase {
    func testSelectsExistingConversationInSameContextFirst() {
        let fallbackContextId = UUID()
        let sameContext = Conversation(
            contextId: fallbackContextId,
            contextFolderPath: "/tmp/project"
        )
        let otherContext = Conversation(contextId: UUID())

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: [otherContext, sameContext],
            fallbackContextId: fallbackContextId,
            fallbackFolderPath: "/tmp/project"
        )

        XCTAssertEqual(result, .selectExisting(sameContext.id))
    }

    func testRepurposesSingleAutoCreatedEmptyGlobalThread() {
        let autoCreated = Conversation(
            messages: [],
            contextId: nil,
            contextFolderPath: nil
        )

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: [autoCreated],
            fallbackContextId: UUID(),
            fallbackFolderPath: "/tmp/project",
            autoCreatedConversationId: autoCreated.id
        )

        XCTAssertEqual(result, SidebarThreadDeletionFallback.repurposeAutoCreatedEmptyThread(autoCreated.id))
    }

    func testDoesNotRepurposeReusableGlobalThreadWithoutExplicitAutoCreatedId() {
        let existingGlobal = Conversation(
            messages: [],
            contextId: nil,
            contextFolderPath: nil
        )

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: [existingGlobal],
            fallbackContextId: UUID(),
            fallbackFolderPath: "/tmp/project"
        )

        XCTAssertEqual(result, SidebarThreadDeletionFallback.createNew)
    }

    func testCreatesNewThreadWhenOnlyRemainingConversationIsNotReusable() {
        let populatedGlobal = Conversation(
            messages: [ChatMessage(role: .user, content: "ciao")],
            contextId: nil,
            contextFolderPath: nil
        )

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: [populatedGlobal],
            fallbackContextId: UUID(),
            fallbackFolderPath: "/tmp/project",
            autoCreatedConversationId: populatedGlobal.id
        )

        XCTAssertEqual(result, SidebarThreadDeletionFallback.createNew)
    }

    func testArchivedConversationInSameContextIsIgnoredForFallbackSelection() {
        let fallbackContextId = UUID()
        let archivedSameContext = Conversation(
            contextId: fallbackContextId,
            contextFolderPath: "/tmp/project",
            isArchived: true
        )
        let autoCreated = Conversation(
            messages: [],
            contextId: nil,
            contextFolderPath: nil
        )

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: [archivedSameContext, autoCreated],
            fallbackContextId: fallbackContextId,
            fallbackFolderPath: "/tmp/project",
            autoCreatedConversationId: autoCreated.id
        )

        XCTAssertEqual(result, SidebarThreadDeletionFallback.repurposeAutoCreatedEmptyThread(autoCreated.id))
    }

    @MainActor
    func testDeleteLastConversationThenFallbackRepurposesAutoCreatedThreadForVisibleRecovery() throws {
        let suiteName = "SidebarThreadDeletionFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatStore(userDefaults: defaults)
        let originalId = try XCTUnwrap(store.conversations.first?.id)
        let fallbackContextId = UUID()
        let fallbackFolderPath = "/tmp/project"

        store.setContext(conversationId: originalId, contextId: fallbackContextId)
        store.setContextFolder(conversationId: originalId, folderPath: fallbackFolderPath)

        let deletionOutcome = store.deleteConversation(id: originalId)

        XCTAssertEqual(store.conversations.count, 1)
        let autoCreated = try XCTUnwrap(store.conversations.first)
        XCTAssertNotEqual(autoCreated.id, originalId)
        XCTAssertNil(autoCreated.contextId)
        XCTAssertNil(autoCreated.contextFolderPath)

        let result = resolveSidebarThreadDeletionFallback(
            remainingConversations: store.conversations,
            fallbackContextId: fallbackContextId,
            fallbackFolderPath: fallbackFolderPath,
            autoCreatedConversationId: deletionOutcome.autoCreatedReplacementId
        )

        XCTAssertEqual(result, SidebarThreadDeletionFallback.repurposeAutoCreatedEmptyThread(autoCreated.id))
    }
}
