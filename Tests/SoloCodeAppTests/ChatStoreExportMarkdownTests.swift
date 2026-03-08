import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreExportMarkdownTests: XCTestCase {
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

    func testExportIncludesHeaderSectionsAndNonImageAttachments() throws {
        let store = ChatStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.conversations[0] = Conversation(
            id: conversationId,
            title: "Release Notes",
            messages: [
                ChatMessage(role: .user, content: "Prepare summary", isStreaming: false),
                ChatMessage(
                    role: .assistant,
                    content: "Summary ready",
                    isStreaming: false,
                    attachments: [
                        ChatAttachment(kind: .image, originalName: "preview.png", localPath: "/tmp/preview.png"),
                        ChatAttachment(kind: .document, originalName: "changelog.pdf", localPath: "/tmp/changelog.pdf"),
                    ]
                ),
            ]
        )

        let markdown = try XCTUnwrap(store.exportConversationMarkdown(conversationId: conversationId))
        XCTAssertTrue(markdown.contains("# Release Notes"))
        XCTAssertTrue(markdown.contains("Exported:"))
        XCTAssertTrue(markdown.contains("## You"))
        XCTAssertTrue(markdown.contains("## Assistant"))
        XCTAssertTrue(markdown.contains("Attachments:"))
        XCTAssertTrue(markdown.contains("- changelog.pdf"))
        XCTAssertFalse(markdown.contains("- preview.png"))
    }

    func testExportSkipsWhitespaceOnlyMessages() throws {
        let store = ChatStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        store.conversations[0] = Conversation(
            id: conversationId,
            title: "Thread",
            messages: [
                ChatMessage(role: .user, content: "   \n ", isStreaming: false),
                ChatMessage(role: .assistant, content: "Final", isStreaming: false),
            ]
        )

        let markdown = try XCTUnwrap(store.exportConversationMarkdown(conversationId: conversationId))
        XCTAssertFalse(markdown.contains("## You"))
        XCTAssertTrue(markdown.contains("## Assistant"))
    }

    func testExportIncludesPipelineBlocksWhenPresent() throws {
        let store = ChatStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)

        let assistant = ChatMessage(
            role: .assistant,
            content: "",
            primaryTextSnapshot: "Primary response",
            blocks: [
                PersistedChatTimelineBlock(
                    id: "primary-text",
                    kind: .primaryText,
                    text: "Primary response"
                ),
                PersistedChatTimelineBlock(
                    id: "mermaid-1",
                    kind: .mermaid,
                    title: "Flow",
                    text: "graph TD; A-->B;",
                    isCollapsible: true
                ),
                PersistedChatTimelineBlock(
                    id: "commands",
                    kind: .commands,
                    title: "Commands executed",
                    items: ["swift test"],
                    isCollapsible: true,
                    isCollapsedByDefault: true
                ),
            ]
        )

        store.conversations[0] = Conversation(
            id: conversationId,
            title: "Pipeline Export",
            messages: [assistant]
        )

        let markdown = try XCTUnwrap(store.exportConversationMarkdown(conversationId: conversationId))
        XCTAssertTrue(markdown.contains("Primary response"))
        XCTAssertTrue(markdown.contains("```mermaid"))
        XCTAssertTrue(markdown.contains("swift test"))
    }

    func testDefaultMarkdownFilenameSanitizesTitle() throws {
        let store = ChatStore()
        let conversationId = try XCTUnwrap(store.conversations.first?.id)
        store.setTitle(conversationId: conversationId, title: #"Roadmap: Q1/Q2   update"#)

        let filename = store.defaultMarkdownFilename(for: conversationId)
        XCTAssertTrue(filename.hasSuffix(".md"))
        XCTAssertFalse(filename.contains("/"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains(" "))
    }

    func testDefaultMarkdownFilenameFallsBackToChat() {
        let store = ChatStore()
        XCTAssertEqual(store.defaultMarkdownFilename(for: nil), "chat.md")
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: convKey)
        UserDefaults.standard.removeObject(forKey: planKey)
    }
}
