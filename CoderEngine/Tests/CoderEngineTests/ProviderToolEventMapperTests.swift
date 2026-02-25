import XCTest
@testable import CoderEngine

final class ProviderToolEventMapperTests: XCTestCase {
    func testSearchToolMapsToInstantGrep() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Search",
            payload: [
                "query": "debug panel",
                "pathScope": "Sources/CoderIDE",
            ]
        )

        XCTAssertEqual(mapped?.type, "instant_grep")
        XCTAssertEqual(mapped?.payload["query"], "debug panel")
        XCTAssertEqual(mapped?.payload["pathScope"], "Sources/CoderIDE")
    }

    func testReadRangeMapsToReadBatchCompleted() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "read_range",
            payload: [
                "path": "/tmp/file.swift",
                "output": "line1\nline2",
            ]
        )

        XCTAssertEqual(mapped?.type, "read_batch_completed")
        XCTAssertEqual(mapped?.payload["path"], "/tmp/file.swift")
        XCTAssertEqual(mapped?.payload["file"], "/tmp/file.swift")
    }

    func testMCPCallMapsToMCPToolCall() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "xcodebuild",
                "mcp_tool": "run_tests",
                "detail": "execute tests",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["mcp_server"], "xcodebuild")
        XCTAssertEqual(mapped?.payload["mcp_tool"], "run_tests")
    }

    func testUnknownToolFallsBackToCommandExecution() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "custom_tool",
            payload: ["detail": "custom payload"]
        )

        XCTAssertEqual(mapped?.type, "command_execution")
        XCTAssertEqual(mapped?.payload["tool"], "custom_tool")
    }

    func testNamespacedExecCommandMapsToCommandExecution() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.exec_command",
            payload: [
                "cmd": "git status --short"
            ]
        )

        XCTAssertEqual(mapped?.type, "command_execution")
        XCTAssertEqual(mapped?.payload["tool"], "bash")
        XCTAssertEqual(mapped?.payload["command"], "git status --short")
    }

    func testNamespacedSemanticSearchWithJSONStringArgsMapsToSemanticSearch() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.semantic_search",
            payload: [
                "arguments": #"{"query":"trace activity","num_results":8}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "semantic_search")
        XCTAssertEqual(mapped?.payload["query"], "trace activity")
        XCTAssertEqual(mapped?.payload["tool"], "semantic_search")
    }

    func testNamespacedMCPListServersMapsToMCPToolCall() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.mcp_list_servers",
            payload: [:]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["tool"], "mcp_list_servers")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("MCP discovery"))
    }
}
