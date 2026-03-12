import XCTest
import MCP
import CoderEngine
@testable import CoderIDEMCPServer

extension BugHunterHandlerTests {
    func testBugHunterStartRejectsInvalidSourceKindViaRustPrelude() {
        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_start",
            args: ["source_kind": "invalid"]
        )

        XCTAssertEqual(result?.isError, true)
        let text: String
        if let first = result?.content.first, case .text(let value) = first {
            text = value
        } else {
            text = ""
        }
        XCTAssertTrue(text.contains("invalid source_kind"))
    }
}
