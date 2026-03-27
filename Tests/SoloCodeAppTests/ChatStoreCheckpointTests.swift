import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreCheckpointTests: XCTestCase {
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

    func testCreateCheckpointPersistsGitMetadata() throws {
        let store = ChatStore()
        let convId = try conversationID(from: store)
        store.addMessage(ChatMessage(role: .user, content: "hello"), to: convId)

        let gitState = ConversationCheckpointGitState(
            gitRootPath: "/tmp/repo",
            gitSnapshotRef: "abc123"
        )
        store.createCheckpoint(for: convId, gitStates: [gitState])

        let checkpoint = store.conversation(for: convId)?.checkpoints.last
        XCTAssertEqual(checkpoint?.messageCount, 1)
        XCTAssertEqual(checkpoint?.gitStates, [gitState])
    }

    func testRewindConversationStateTrimsMessagesAndPlanBoard() throws {
        let store = ChatStore()
        let convId = try conversationID(from: store)
        store.addMessage(ChatMessage(role: .user, content: "m1"), to: convId)
        let board = PlanBoard(goal: "goal", options: [PlanOption(id: 1, title: "A", fullText: "A")], chosenPath: nil, steps: [], updatedAt: .now)
        store.setPlanBoard(board, for: convId)
        store.createCheckpoint(for: convId, gitStates: [])
        guard let cpId = store.previousCheckpoint(conversationId: convId)?.id else {
            XCTFail("Checkpoint missing")
            return
        }

        store.addMessage(ChatMessage(role: .assistant, content: "m2"), to: convId)
        store.setPlanBoard(PlanBoard(goal: "changed", options: [], chosenPath: nil, steps: [], updatedAt: .now), for: convId)

        let ok = store.rewindConversationState(to: cpId, conversationId: convId)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.conversation(for: convId)?.messages.count, 1)
        XCTAssertEqual(store.planBoard(for: convId)?.goal, "goal")
        XCTAssertFalse(store.canRewind(conversationId: convId))
    }

    func testTrimFutureCheckpointsRemovesNewerMessageCounts() throws {
        let store = ChatStore()
        let convId = try conversationID(from: store)
        store.addMessage(ChatMessage(role: .user, content: "a"), to: convId)
        store.createCheckpoint(for: convId, gitStates: [])
        store.addMessage(ChatMessage(role: .assistant, content: "b"), to: convId)
        store.createCheckpoint(for: convId, gitStates: [])
        store.addMessage(ChatMessage(role: .user, content: "c"), to: convId)

        store.trimFutureCheckpoints(conversationId: convId, maxMessageCount: 1)
        let cps = store.conversation(for: convId)?.checkpoints ?? []
        XCTAssertEqual(cps.count, 1)
        XCTAssertEqual(cps.first?.messageCount, 1)
    }

    func testCheckpointLookupUsesZeroBasedMessageIndex() throws {
        let store = ChatStore()
        let convId = try conversationID(from: store)
        store.addMessage(ChatMessage(role: .user, content: "first"), to: convId)
        store.createCheckpoint(for: convId, gitStates: [])
        store.addMessage(ChatMessage(role: .assistant, content: "reply"), to: convId)
        store.addMessage(ChatMessage(role: .user, content: "second"), to: convId)
        store.createCheckpoint(for: convId, gitStates: [])

        let firstCheckpoint = store.checkpoint(forMessageIndex: 0, conversationId: convId)
        let secondCheckpoint = store.checkpoint(forMessageIndex: 2, conversationId: convId)

        XCTAssertNotNil(firstCheckpoint)
        XCTAssertEqual(firstCheckpoint?.messageCount, 1)
        XCTAssertNotNil(secondCheckpoint)
        XCTAssertEqual(secondCheckpoint?.messageCount, 3)
    }

    func testRewindConversationStateRestoresLinkedPlanConversationSnapshot() throws {
        let store = ChatStore()
        let agentConversationId = try conversationID(from: store)
        let planConversationId = store.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: .plan
        )

        let initialPlanBoard = PlanBoard(
            goal: "Initial goal",
            options: [],
            chosenPath: nil,
            steps: [],
            updatedAt: .now,
            walkthroughMarkdown: "Initial walkthrough"
        )
        store.setPlanBoard(initialPlanBoard, for: planConversationId)

        store.addMessage(ChatMessage(role: .user, content: "start build"), to: agentConversationId)
        store.createCheckpoint(
            for: agentConversationId,
            gitStates: [],
            planConversationIdForSnapshot: planConversationId
        )
        guard let checkpointId = store.previousCheckpoint(conversationId: agentConversationId)?.id else {
            XCTFail("Checkpoint missing")
            return
        }

        store.setPlanBoard(
            PlanBoard(
                goal: "Mutated goal",
                options: [],
                chosenPath: nil,
                steps: [],
                updatedAt: .now,
                walkthroughMarkdown: "Mutated walkthrough"
            ),
            for: planConversationId
        )
        store.addMessage(ChatMessage(role: .assistant, content: "build response"), to: agentConversationId)

        let ok = store.rewindConversationState(to: checkpointId, conversationId: agentConversationId)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.conversation(for: agentConversationId)?.messages.count, 1)
        XCTAssertEqual(store.planBoard(for: planConversationId)?.goal, "Initial goal")
        XCTAssertEqual(store.planBoard(for: planConversationId)?.walkthroughMarkdown, "Initial walkthrough")
    }

    func testRewindConversationStateClearsStaleLinkedPlanBoardWhenTargetCheckpointHasNoLinkedSnapshot() throws {
        let store = ChatStore()
        let agentConversationId = try conversationID(from: store)
        let linkedPlanConversationId = store.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: .plan
        )

        store.addMessage(ChatMessage(role: .user, content: "plain"), to: agentConversationId)
        store.createCheckpoint(for: agentConversationId, gitStates: [])
        guard let initialCheckpointId = store.previousCheckpoint(conversationId: agentConversationId)?.id else {
            XCTFail("Initial checkpoint missing")
            return
        }

        store.setPlanBoard(
            PlanBoard(goal: "Linked goal", options: [], chosenPath: nil, steps: [], updatedAt: .now),
            for: linkedPlanConversationId
        )
        store.addMessage(ChatMessage(role: .assistant, content: "build"), to: agentConversationId)
        store.createCheckpoint(
            for: agentConversationId,
            gitStates: [],
            planConversationIdForSnapshot: linkedPlanConversationId
        )

        let ok = store.rewindConversationState(to: initialCheckpointId, conversationId: agentConversationId)
        XCTAssertTrue(ok)
        XCTAssertNil(store.planBoard(for: linkedPlanConversationId))
    }

    func testRewindConversationToMessageCountClearsLinkedPlanBoardWhenNoCheckpointRemains() throws {
        let store = ChatStore()
        let agentConversationId = try conversationID(from: store)
        let linkedPlanConversationId = store.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: .plan
        )

        store.setPlanBoard(
            PlanBoard(goal: "Linked goal", options: [], chosenPath: nil, steps: [], updatedAt: .now),
            for: linkedPlanConversationId
        )
        store.addMessage(ChatMessage(role: .user, content: "start"), to: agentConversationId)
        store.createCheckpoint(
            for: agentConversationId,
            gitStates: [],
            planConversationIdForSnapshot: linkedPlanConversationId
        )

        let ok = store.rewindConversationToMessageCount(0, conversationId: agentConversationId)
        XCTAssertTrue(ok)
        XCTAssertNil(store.planBoard(for: agentConversationId))
        XCTAssertNil(store.planBoard(for: linkedPlanConversationId))
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }

    private func conversationID(from store: ChatStore) throws -> UUID {
        try XCTUnwrap(store.conversations.first?.id, "Conversation missing")
    }
}
