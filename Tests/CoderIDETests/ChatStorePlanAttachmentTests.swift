import XCTest
@testable import CoderIDE

@MainActor
final class ChatStorePlanAttachmentTests: XCTestCase {
    private let convKey = "CoderIDE.conversations"
    private let historyKey = "CoderIDE.planHistory"
    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("CoderIDE", isDirectory: true)
            .appendingPathComponent("planHistory.json")
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        try? FileManager.default.removeItem(at: historyFileURL)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        try? FileManager.default.removeItem(at: historyFileURL)
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
        let conv = Conversation(title: "test", messages: [message], mode: .agent)
        let data = try JSONEncoder().encode([conv])
        UserDefaults.standard.set(data, forKey: convKey)

        let chat = ChatStore()
        let history = PlanHistoryStore()

        chat.backfillPlanAttachmentsIfNeeded(historyStore: history)
        chat.backfillPlanAttachmentsIfNeeded(historyStore: history)

        XCTAssertEqual(history.entries.count, 1)
        let loaded = chat.conversations.first?.messages.first
        XCTAssertNotNil(loaded?.planAttachment)
    }
}
