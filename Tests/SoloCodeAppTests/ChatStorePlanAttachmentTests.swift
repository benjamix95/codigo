import XCTest
@testable import CoderIDE

@MainActor
final class ChatStorePlanAttachmentTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let historyKey = "CoderIDE.planHistory"
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ChatStorePlanAttachmentTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults.removeObject(forKey: convKey)
        isolatedDefaults.removeObject(forKey: historyKey)
    }

    override func tearDown() {
        isolatedDefaults.removeObject(forKey: convKey)
        isolatedDefaults.removeObject(forKey: historyKey)
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLegacyChatMessageDecodeWithoutPlanAttachment() throws {
        let raw = """
        {"id":"\(UUID().uuidString)","role":"assistant","content":"hello","isStreaming":false}
        """
        let data = try XCTUnwrap(raw.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertNil(decoded.planAttachment)
    }

    func testBackfillCreatesSingleEntryAndAttachmentIdempotent() throws {
        let message = ChatMessage(
            role: .assistant,
            content: """
            ## Option 1: Robust fix
            ## Todo
            - [ ] Improve isolation

            ## Option 2: Fast patch
            ## Todo
            - [ ] Apply targeted fix
            """,
            isStreaming: false
        )
        let chat = ChatStore(userDefaults: isolatedDefaults)
        chat.conversations = []
        let conversationId = chat.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: .agent
        )
        chat.addMessage(message, to: conversationId)

        let suiteName = "ChatStorePlanAttachmentTests.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        let isolatedHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("planHistory-\(UUID().uuidString).json")
        defer {
            isolatedDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: isolatedHistoryURL)
        }
        let history = PlanHistoryStore(
            userDefaults: isolatedDefaults,
            storageURL: isolatedHistoryURL
        )

        chat.backfillPlanAttachmentsIfNeeded(historyStore: history)
        chat.backfillPlanAttachmentsIfNeeded(historyStore: history)

        XCTAssertEqual(history.entries.count, 1)
        let loaded = chat.conversation(for: conversationId)?.messages.first
        XCTAssertNotNil(loaded?.planAttachment)
    }

    func testBackfillReusesLegacyHashMatchWithoutSelectingConversation() throws {
        let message = ChatMessage(
            role: .assistant,
            content: """
            ## Option 1: Robust fix
            ## Todo
            - [ ] Improve isolation
            """,
            isStreaming: false
        )
        let chat = ChatStore(userDefaults: isolatedDefaults)
        chat.conversations = []
        let conversationId = chat.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: .agent
        )
        chat.addMessage(message, to: conversationId)

        let suiteName = "ChatStorePlanAttachmentTests.\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        let isolatedHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("planHistory-\(UUID().uuidString).json")
        defer {
            isolatedDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: isolatedHistoryURL)
        }
        let history = PlanHistoryStore(
            userDefaults: isolatedDefaults,
            storageURL: isolatedHistoryURL
        )
        let legacyEntry = history.createEntry(
            conversationId: conversationId,
            contextId: nil,
            contextFolderPath: nil,
            title: "Legacy entry",
            markdown: message.content,
            options: [],
            chosenPath: nil,
            tags: [],
            sourceMessageId: nil,
            selectForConversation: false
        )
        history.setSelectedEntry(id: nil, conversationId: conversationId)

        chat.backfillPlanAttachmentsIfNeeded(historyStore: history)

        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.findEntry(id: legacyEntry.id)?.sourceMessageId, message.id)
        XCTAssertNil(history.selectedEntryId(for: conversationId))
        let loaded = chat.conversation(for: conversationId)?.messages.first
        XCTAssertEqual(loaded?.planAttachment?.historyEntryId, legacyEntry.id)
    }
}
