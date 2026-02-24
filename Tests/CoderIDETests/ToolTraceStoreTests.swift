import XCTest
@testable import CoderIDE

@MainActor
final class ToolTraceStoreTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        cleanup(conversationId: testConversationId, assistantMessageId: testAssistantMessageId)
    }

    private let testConversationId = UUID()
    private let testAssistantMessageId = UUID()

    func testAppendAndReloadFromDiskPreservesOrderAndPayload() {
        let store = ToolTraceStore()
        store.startTurn(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            providerId: "codex-cli"
        )

        let payload = String(repeating: "x", count: 512)
        store.append(event: ToolTraceEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 10),
            providerId: "codex-cli",
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            type: "command_execution",
            title: "Run command",
            detail: "started",
            payload: ["output": payload],
            phase: .executing,
            isRunning: true,
            groupId: "g1",
            rawKind: "terminal_session"
        ))
        store.append(event: ToolTraceEvent(
            sequence: 2,
            timestamp: Date(timeIntervalSince1970: 11),
            providerId: "codex-cli",
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            type: "command_execution",
            title: "Run command",
            detail: "completed",
            payload: ["status": "completed"],
            phase: .executing,
            isRunning: false,
            groupId: "g1",
            rawKind: "terminal_session"
        ))

        let inMemory = store.events(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId
        )
        XCTAssertEqual(inMemory.map(\.sequence), [1, 2])
        XCTAssertEqual(inMemory.first?.payload["output"], payload)

        let reloaded = ToolTraceStore().events(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId
        )
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.map(\.sequence), [1, 2])
        XCTAssertEqual(reloaded.first?.payload["output"], payload)
    }

    func testHasTraceReflectsPersistedData() {
        let store = ToolTraceStore()
        XCTAssertFalse(store.hasTrace(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId
        ))

        store.startTurn(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            providerId: "codex-cli"
        )
        store.append(event: ToolTraceEvent(
            sequence: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            providerId: "codex-cli",
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId,
            type: "web_search_started",
            title: "Search",
            detail: nil,
            payload: ["query": "swiftui"],
            phase: .searching,
            isRunning: true,
            groupId: "q1",
            rawKind: "instant_grep"
        ))

        XCTAssertTrue(store.hasTrace(
            conversationId: testConversationId,
            assistantMessageId: testAssistantMessageId
        ))
    }

    private func cleanup(conversationId: UUID, assistantMessageId _: UUID) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport
            .appendingPathComponent("Codigo", isDirectory: true)
            .appendingPathComponent("ToolTrace", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(conversationId.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
