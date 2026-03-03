import XCTest
@testable import CoderIDE

final class MermaidRenderingTests: XCTestCase {
    func testRenderingHTMLUsesExplicitMermaidRunForDynamicLoad() {
        let html = MermaidWebView.renderingHTML(
            for: "graph TD; A-->B",
            isDarkMode: false
        )

        XCTAssertTrue(html.contains("querySelectorAll('.mermaid')"))
        XCTAssertTrue(html.contains("mermaid.run"))
        XCTAssertTrue(html.contains("mermaid.initialize"))
    }
}
