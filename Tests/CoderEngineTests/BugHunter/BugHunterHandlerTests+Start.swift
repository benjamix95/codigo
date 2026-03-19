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

    func testBugHunterStartFailsClosedWhenRustCoreIsForcedOff() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_start",
            args: ["source_kind": "uncommitted"]
        )

        XCTAssertEqual(result?.isError, true)
        let text: String
        if let first = result?.content.first, case .text(let value) = first {
            text = value
        } else {
            text = ""
        }
        XCTAssertTrue(text.contains("Rust review core unavailable for bughunter_start"))
    }
}

final class BugHunterHandlerFailClosedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testBugHunterStartFailsClosedWhenRustCoreIsForcedOff() {
        let result = CoderIDEMCPServerApp.handleBugHunterTool(
            name: "bughunter_start",
            args: ["source_kind": "uncommitted"]
        )

        XCTAssertEqual(result?.isError, true)
        let text: String
        if let first = result?.content.first, case .text(let value) = first {
            text = value
        } else {
            text = ""
        }
        XCTAssertTrue(text.contains("Rust review core unavailable for bughunter_start"))
    }
}
