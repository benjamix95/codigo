import SwiftUI
import XCTest
@testable import CoderIDE

final class MarkdownFileReferenceLinkingTests: XCTestCase {
    func testFileReferenceLinkingWorksWithMarkdownPrefix() {
        let view = MarkdownContentView(content: "", context: nil, onFileClicked: { _ in })
        let attributed = view.buildInlineAttributed(
            "**controlla** Sources/App/main.swift:12",
            fontSize: 12,
            fontWeight: .regular,
            color: nil
        )

        let links = extractedLinks(from: attributed)
        XCTAssertFalse(links.isEmpty)
        XCTAssertTrue(
            links.contains { linked in
                linked.text.contains("Sources/App/main.swift")
                    && linked.url.path.hasSuffix("/Sources/App/main.swift")
            }
        )
    }

    func testFileReferenceLinkingStripsLineAndColumnSuffix() {
        let view = MarkdownContentView(content: "", context: nil, onFileClicked: { _ in })
        let attributed = view.buildInlineAttributed(
            "Vedi /tmp/demo.swift:10:2",
            fontSize: 12,
            fontWeight: .regular,
            color: nil
        )

        let links = extractedLinks(from: attributed)
        XCTAssertTrue(
            links.contains { linked in
                linked.text.contains("/tmp/demo.swift:10:2")
                    && linked.url.path == "/tmp/demo.swift"
            }
        )
    }

    private func extractedLinks(from attributed: AttributedString) -> [(text: String, url: URL)] {
        var result: [(text: String, url: URL)] = []
        for run in attributed.runs {
            guard let url = run.link else { continue }
            let text = String(attributed[run.range].characters)
            result.append((text: text, url: url))
        }
        return result
    }
}
