import Combine
import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreTaskOwnershipTests: XCTestCase {
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

    func testBeginTaskTracksConversationId() throws {
        let store = ChatStore()
        let convId = try XCTUnwrap(store.conversations.first?.id)

        store.beginTask(conversationId: convId)

        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.activeTaskConversationId, convId)
        XCTAssertNotNil(store.taskStartDate)
    }

    func testBeginTaskFallsBackWhenRustTaskRuntimeIsUnavailable() throws {
        let original = getenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT").map { String(cString: $0) }
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            if let original {
                setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", original, 1)
            } else {
                unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            }
        }

        let store = ChatStore()
        let convId = try XCTUnwrap(store.conversations.first?.id)

        store.beginTask(conversationId: convId)

        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.activeTaskConversationId, convId)
        XCTAssertEqual(store.taskStatusTexts[convId], "Thinking")
        XCTAssertNotNil(store.taskStartDates[convId])
    }

    func testEndTaskClearsOnlyMatchingConversationId() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.beginTask(conversationId: convA)
        store.endTask(conversationId: convB)

        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.activeTaskConversationId, convA)

        store.endTask(conversationId: convA)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.activeTaskConversationId)
    }

    func testSetTaskStatusDoesNotCreateInactiveTaskState() throws {
        let store = ChatStore()
        let convId = try XCTUnwrap(store.conversations.first?.id)

        store.setTaskStatus("Testing", for: convId)

        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.activeTaskConversationIds.contains(convId))
        XCTAssertNil(store.taskStartDates[convId])
        XCTAssertNil(store.taskStatusTexts[convId])
    }

    func testCreateConversationAlwaysReturnsNewId() {
        let store = ChatStore()
        let id1 = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        let id2 = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        XCTAssertNotEqual(id1, id2)
    }

    func testActiveTaskConversationIdPrefersMostRecentTaskStartDate() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.beginTask(conversationId: convA)
        store.beginTask(conversationId: convB)

        // Force deterministic ordering for the test.
        store.taskStartDates[convA] = Date(timeIntervalSince1970: 1_000)
        store.taskStartDates[convB] = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(store.activeTaskConversationId, convB)
        XCTAssertEqual(store.taskStartDate, Date(timeIntervalSince1970: 2_000))
    }

    func testPreferredPlanConversationIdForCanonicalSyncPrefersActiveTaskWithPlanBoard() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.setPlanBoard(makePlanBoard(updatedAt: Date(timeIntervalSince1970: 1_000)), for: convA)
        store.setPlanBoard(makePlanBoard(updatedAt: Date(timeIntervalSince1970: 2_000)), for: convB)
        store.beginTask(conversationId: convA)
        store.beginTask(conversationId: convB)
        store.taskStartDates[convA] = Date(timeIntervalSince1970: 3_000)
        store.taskStartDates[convB] = Date(timeIntervalSince1970: 4_000)

        XCTAssertEqual(store.preferredPlanConversationIdForCanonicalSync(), convB)
    }

    func testPreferredPlanConversationIdForCanonicalSyncFallsBackToLatestBoard() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.setPlanBoard(makePlanBoard(updatedAt: Date(timeIntervalSince1970: 1_000)), for: convA)
        store.setPlanBoard(makePlanBoard(updatedAt: Date(timeIntervalSince1970: 2_000)), for: convB)

        XCTAssertEqual(store.preferredPlanConversationIdForCanonicalSync(), convB)
    }

    func testDeleteConversationClearsActiveTaskStateForDeletedId() throws {
        let store = ChatStore()
        let convA = try XCTUnwrap(store.conversations.first?.id)
        let convB = store.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        store.beginTask(conversationId: convA)
        store.beginTask(conversationId: convB)
        store.taskStartDates[convA] = Date(timeIntervalSince1970: 3_000)
        store.taskStartDates[convB] = Date(timeIntervalSince1970: 4_000)
        XCTAssertEqual(store.activeTaskConversationId, convB)

        store.deleteConversation(id: convB)

        XCTAssertFalse(store.activeTaskConversationIds.contains(convB))
        XCTAssertNil(store.taskStartDates[convB])
        XCTAssertNil(store.taskStatusTexts[convB])
        XCTAssertEqual(store.activeTaskConversationId, convA)
        XCTAssertTrue(store.isLoading)
    }

    func testDeleteLastConversationAutoCreatesReplacementThread() throws {
        let store = ChatStore()
        let onlyConversationId = try XCTUnwrap(store.conversations.first?.id)

        let deletionOutcome = store.deleteConversation(id: onlyConversationId)

        XCTAssertEqual(store.conversations.count, 1)
        let replacement = try XCTUnwrap(store.conversations.first)
        XCTAssertNotEqual(replacement.id, onlyConversationId)
        XCTAssertTrue(replacement.messages.isEmpty)
        XCTAssertNil(replacement.contextId)
        XCTAssertNil(replacement.contextFolderPath)
        XCTAssertEqual(deletionOutcome.autoCreatedReplacementId, replacement.id)
    }

    func testFlushConversationChangeNotificationPublishesPendingStreamingMutationImmediately() throws {
        let store = ChatStore()
        let convId = try XCTUnwrap(store.conversations.first?.id)
        store.beginTask(conversationId: convId)

        var emissionCount = 0
        let firstEmission = expectation(description: "first streaming mutation publishes")
        let flushed = expectation(description: "flush publishes pending conversation mutation")
        let cancellable = store.objectWillChange.sink {
            emissionCount += 1
            if emissionCount == 1 {
                firstEmission.fulfill()
            } else if emissionCount >= 2 {
                flushed.fulfill()
            }
        }
        defer { cancellable.cancel() }

        try mutateConversation(in: store, conversationId: convId, assistantContent: "first")
        wait(for: [firstEmission], timeout: 0.05)

        try mutateConversation(in: store, conversationId: convId, assistantContent: "second")
        XCTAssertEqual(emissionCount, 1)

        store.flushConversationChangeNotification()

        wait(for: [flushed], timeout: 0.05)
        XCTAssertGreaterThanOrEqual(emissionCount, 2)
    }

    private func makePlanBoard(updatedAt: Date) -> PlanBoard {
        PlanBoard(
            goal: "Goal",
            options: [],
            chosenPath: nil,
            steps: [
                PlanStep(
                    id: "1",
                    title: "Step",
                    description: "Step",
                    targetFile: nil,
                    status: .pending
                )
            ],
            updatedAt: updatedAt,
            walkthroughMarkdown: nil
        )
    }

    private func mutateConversation(
        in store: ChatStore,
        conversationId: UUID,
        assistantContent: String
    ) throws {
        let index = try XCTUnwrap(store.conversations.firstIndex(where: { $0.id == conversationId }))
        var conversation = store.conversations[index]
        conversation.messages = [
            ChatMessage(role: .assistant, content: assistantContent, isStreaming: true)
        ]
        store.conversations[index] = conversation
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
