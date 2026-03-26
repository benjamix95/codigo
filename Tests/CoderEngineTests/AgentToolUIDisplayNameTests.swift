import XCTest
@testable import CoderEngine

final class AgentToolUIDisplayNameTests: XCTestCase {
    func testWorkspaceToolLabelsAreExplicit() {
        XCTAssertEqual(AgentToolUIDisplayName.label(forRuntimeTool: "grep"), "Grep in workspace")
        XCTAssertEqual(AgentToolUIDisplayName.label(forRuntimeTool: "write"), "Write to workspace file")
        XCTAssertEqual(AgentToolUIDisplayName.label(forRuntimeTool: "create_file"), "Create workspace file")
        XCTAssertEqual(AgentToolUIDisplayName.label(forRuntimeTool: "bash"), "Terminal command")
    }

    func testTitledJoinsDetailWithBullet() {
        XCTAssertEqual(
            AgentToolUIDisplayName.titled("Grep in workspace", detail: "foo"),
            "Grep in workspace • foo"
        )
        XCTAssertEqual(AgentToolUIDisplayName.titled("Read workspace file", detail: "  "), "Read workspace file")
    }
}
