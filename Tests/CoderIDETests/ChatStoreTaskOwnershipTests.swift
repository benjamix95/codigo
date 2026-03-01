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

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
