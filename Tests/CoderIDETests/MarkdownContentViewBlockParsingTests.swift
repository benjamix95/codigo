import XCTest
@testable import CoderIDE

final class MarkdownContentViewBlockParsingTests: XCTestCase {
    func testInlineMermaidFenceParsesAsMermaidBlock() {
        let view = MarkdownContentView(
            content: "```mermaid graph TD; A-->B```",
            context: nil,
            onFileClicked: { _ in }
        )

        let blocks = view.parseBlocksForTests()
        let hasInlineMermaid = blocks.contains { block in
            if case .mermaid(let code) = block {
                return code == "graph TD; A-->B"
            }
            return false
        }
        XCTAssertTrue(hasInlineMermaid)
    }

    func testInlineCodeFenceParsesLanguageAndCode() {
        let view = MarkdownContentView(
            content: "```swift let value = 1```",
            context: nil,
            onFileClicked: { _ in }
        )

        let blocks = view.parseBlocksForTests()
        let hasInlineCode = blocks.contains { block in
            if case .codeBlock(let language, let code) = block {
                return language == "swift" && code == "let value = 1"
            }
            return false
        }
        XCTAssertTrue(hasInlineCode)
    }

    func testPipeRowsWithoutValidSeparatorDoNotParseAsTable() {
        let view = MarkdownContentView(
            content: """
            | Name | Value |
            | release-note | v1 |
            | app | codigo |
            """,
            context: nil,
            onFileClicked: { _ in }
        )

        let blocks = view.parseBlocksForTests()
        let hasTable = blocks.contains { block in
            if case .table = block { return true }
            return false
        }
        XCTAssertFalse(hasTable)
    }
}
