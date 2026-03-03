import XCTest
@testable import CoderIDE

final class MarkdownContentFormattingTests: XCTestCase {
    func testNormalizeAssistantDisplayLayoutSeparatesInlineNumberedList() {
        let input = """
        Verification outcome completed with two discrepancies found. 1. High severity: task panel does not open outside swarm. 2. Medium severity: TODO state mismatch.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("found.\n\n1. High severity"))
        XCTAssertTrue(output.contains("\n2. Medium severity"))
    }

    func testNormalizeAssistantDisplayLayoutKeepsCodeFenceUnchanged() {
        let input = """
        First description. ```swift
        let text = "1. is not a list"
        ``` After explanation.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("```swift\nlet text = \"1. is not a list\"\n```"))
    }

    func testNormalizeAssistantDisplayLayoutSplitsDenseSingleLineParagraph() {
        let input = """
        This is a very long paragraph designed to simulate a response that is too compact and hard to read in chat. It contains several consecutive sentences that would normally have more visual breathing room. The goal is to verify that normalization produces natural breaks without altering the meaning of the content. This improves overall readability when the model returns everything on a single line. Finally we check that the text maintains order and a professional tone.
        """

        let output = MarkdownContentView.normalizeAssistantDisplayLayout(input)

        XCTAssertTrue(output.contains("\n\n"), "Expected at least one auto paragraph break")
    }

    func testNormalizeDisplayLayoutCanBeDisabledForUserMessages() {
        let input = """
        This is a very long paragraph designed to verify that user messages remain untouched when normalization is disabled. It contains several consecutive sentences and normally would be split into smaller chunks by assistant layout normalization. We keep this line intentionally dense so the formatting change is easy to detect in tests. The text should remain a single block once rendered in user bubbles.
        """

        let normalized = MarkdownContentView(
            content: input,
            context: nil,
            onFileClicked: { _ in }
        ).displayContent
        let untouched = MarkdownContentView(
            content: input,
            context: nil,
            onFileClicked: { _ in },
            normalizeDisplayLayout: false
        ).displayContent

        XCTAssertTrue(normalized.contains("\n\n"))
        XCTAssertFalse(untouched.contains("\n\n"))
    }
}
