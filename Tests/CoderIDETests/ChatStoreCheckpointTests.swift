import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreCheckpointTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let planKey = "CoderIDE.planBoards"

    override func setUp() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }

    func testCreateCheckpointPersistsGitMetadata() {
        let store = ChatStore()
        guard let convId = store.conversations.first?.id else {
            XCTFail("Conversation mancante")
            return
        }
        store.addMessage(ChatMessage(role: .user, content: "ciao"), to: convId)

        let gitState = ConversationCheckpointGitState(
            gitRootPath: "/tmp/repo",
            gitSnapshotRef: "abc123"
        )
        store.createCheckpoint(for: convId, gitStates: [gitState])

        let checkpoint = store.conversation(for: convId)?.checkpoints.last
        XCTAssertEqual(checkpoint?.messageCount, 1)
        XCTAssertEqual(checkpoint?.gitStates, [gitState])
    }

    func testRewindConversationStateTrimsMessagesAndPlanBoard() {
        let store = ChatStore()
        guard let convId = store.conversations.first?.id else {
            XCTFail("Conversation mancante")
            return
        }
        store.addMessage(ChatMessage(role: .user, content: "m1"), to: convId)
        let board = PlanBoard(goal: "goal", options: [PlanOption(id: 1, title: "A", fullText: "A")], chosenPath: nil, steps: [], updatedAt: .now)
        store.setPlanBoard(board, for: convId)
        store.createCheckpoint(for: convId, gitStates: [])
        guard let cpId = store.previousCheckpoint(conversationId: convId)?.id else {
            XCTFail("Checkpoint mancante")
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

    func testTrimFutureCheckpointsRemovesNewerMessageCounts() {
        let store = ChatStore()
        guard let convId = store.conversations.first?.id else {
            XCTFail("Conversation mancante")
            return
        }
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
}
