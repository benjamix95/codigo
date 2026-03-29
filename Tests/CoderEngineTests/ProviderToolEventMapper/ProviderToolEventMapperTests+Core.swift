import Foundation
import XCTest
@testable import CoderEngine

extension ProviderToolEventMapperTests {
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

    func testGlobInfersMatchesCountFromOutputLinesWhenMissingCountField() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "glob",
            payload: [
                "query": "**/Sources/**/*Subagent*",
                "output": "/tmp/a.swift\n/tmp/b.swift\n",
            ]
        )

        XCTAssertEqual(mapped?.type, "instant_grep")
        XCTAssertEqual(mapped?.payload["matchesCount"], "2")
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
        XCTAssertEqual(mapped?.payload["is_mcp"], "true")
    }

    func testMCPCallPreservesSwarmMetadataFromPayload() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_invoke_swarm",
                "status": "started",
                "tool_call_id": "call-42",
                "swarm_id": "reviewer-42",
                "group_id": "swarm-reviewer-42",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["status"], "started")
        XCTAssertEqual(mapped?.payload["tool_call_id"], "call-42")
        XCTAssertEqual(mapped?.payload["swarm_id"], "reviewer-42")
        XCTAssertEqual(mapped?.payload["group_id"], "swarm-reviewer-42")
    }

    func testMCPInvokeSwarmSynthesizesSwarmMetadataWhenMissing() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_invoke_swarm",
                "tool_call_id": "call-99",
                "status": "completed",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["swarm_id"], "invoke-call-99")
        XCTAssertEqual(mapped?.payload["group_id"], "swarm-invoke-call-99")
        XCTAssertEqual(mapped?.payload["status"], "completed")
    }

    func testMCPInvokeSwarmSynthesizesStableFallbackWhenNoIDsExist() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "invoke_swarm",
                "status": "in_progress",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["swarm_id"], "invoke-swarm")
        XCTAssertEqual(mapped?.payload["group_id"], "swarm-invoke-swarm")
    }

    func testMCPSubagentToolDerivesSwarmMetadataFromToolName() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "subagent_reviewer",
                "status": "started",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["swarm_id"], "reviewer")
        XCTAssertEqual(mapped?.payload["group_id"], "swarm-reviewer")
    }

    func testMCPStrReplaceSummaryInfersLineCounters() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_str_replace",
                "detail": "Replaced at line 1534 (23 lines \u{2192} 55 lines)",
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["linesAdded"], "55")
        XCTAssertEqual(mapped?.payload["linesRemoved"], "23")
        XCTAssertEqual(mapped?.payload["is_mcp"], "true")
    }

    func testMCPStructuredEditOutputPreservesCountersAndDiffPreview() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_str_replace",
                "output": #"{"change_type":"str_replace","diffPreview":"@@ -1 +1 @@\n-let a = 1\n+let a = 2","linesAdded":"1","linesRemoved":"1","path":"Sources/App.swift","source":"mcp","status":"completed","tool_call_id":"tc-123"}"#,
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["path"], "Sources/App.swift")
        XCTAssertEqual(mapped?.payload["diffPreview"], "@@ -1 +1 @@\n-let a = 1\n+let a = 2")
        XCTAssertEqual(mapped?.payload["linesAdded"], "1")
        XCTAssertEqual(mapped?.payload["linesRemoved"], "1")
        XCTAssertEqual(mapped?.payload["source"], "mcp")
        XCTAssertEqual(mapped?.payload["tool_call_id"], "tc-123")
    }

    func testUnknownToolFallsBackToCommandExecution() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "custom_tool",
            payload: ["detail": "custom payload"]
        )

        XCTAssertEqual(mapped?.type, "command_execution")
        XCTAssertEqual(mapped?.payload["tool"], "custom_tool")
    }

    func testMCPLikeNameWithoutMarkerDoesNotMapAsMCP() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "check_mcp_status",
            payload: ["detail": "local preflight"]
        )
        XCTAssertEqual(mapped?.type, "command_execution")
        XCTAssertEqual(mapped?.payload["is_mcp"], nil)
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

    func testNamespacedCoderideSemanticSearchPreservesMCPMetadata() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.coderide_semantic_search",
            payload: [
                "arguments": #"{"query":"trace activity","num_results":8}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "semantic_search")
        XCTAssertEqual(mapped?.payload["query"], "trace activity")
        XCTAssertEqual(mapped?.payload["tool"], "semantic_search")
        XCTAssertEqual(mapped?.payload["is_mcp"], "true")
        XCTAssertEqual(mapped?.payload["mcp_tool"], "coderide_semantic_search")
        XCTAssertEqual(mapped?.payload["mcp_server"], "coderide")
    }

    func testNamespacedCoderideReadPreservesMCPMetadata() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.coderide_read",
            payload: [
                "path": "README.md",
                "content": "hello"
            ]
        )

        XCTAssertEqual(mapped?.type, "read_batch_completed")
        XCTAssertEqual(mapped?.payload["tool"], "read")
        XCTAssertEqual(mapped?.payload["path"], "README.md")
        XCTAssertEqual(mapped?.payload["is_mcp"], "true")
        XCTAssertEqual(mapped?.payload["mcp_tool"], "coderide_read")
        XCTAssertEqual(mapped?.payload["mcp_server"], "coderide")
    }

    func testNamespacedMCPListServersMapsToMCPToolCall() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.mcp_list_servers",
            payload: [:]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["tool"], "mcp_list_servers")
        XCTAssertEqual(mapped?.payload["is_mcp"], "true")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("MCP discovery"))
    }

    func testBenchmarkMCPCallMapsArtifactFieldsAndFriendlyTitle() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.mcp_call",
            payload: [
                "mcp_tool": "coderide_benchmark_indexing",
                "mcp_server": "coderide",
                "status": "completed",
                "output": #"{"tool":"benchmark_indexing","phase":"pre","tag":"bench-1","output_json":"/tmp/bench-1.json","log_file":"/tmp/bench-1.log","summary_md":"/tmp/bench-1.md"}"#,
            ]
        )

        XCTAssertEqual(mapped?.type, "mcp_tool_call")
        XCTAssertEqual(mapped?.payload["title"], "Benchmark • Indexing")
        XCTAssertEqual(mapped?.payload["phase"], "pre")
        XCTAssertEqual(mapped?.payload["tag"], "bench-1")
        XCTAssertEqual(mapped?.payload["output_json"], "/tmp/bench-1.json")
        XCTAssertEqual(mapped?.payload["log_file"], "/tmp/bench-1.log")
        XCTAssertEqual(mapped?.payload["summary_md"], "/tmp/bench-1.md")
        XCTAssertEqual(mapped?.payload["detail"], "pre • bench-1")
    }

    func testApplyPatchMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.apply_patch",
            payload: [
                "path": "App/SoloCodeApp/Sources/MessageToolTraceView.swift",
                "patch": """
                @@ -1 +1 @@
                -old
                +new
                """,
            ]
        )

        XCTAssertEqual(mapped?.type, "file_change")
        XCTAssertEqual(mapped?.payload["tool"], "apply_patch")
        XCTAssertEqual(mapped?.payload["path"], "App/SoloCodeApp/Sources/MessageToolTraceView.swift")
        XCTAssertNotNil(mapped?.payload["diffPreview"])
    }

    // MARK: - Claude CLI Native Tool Name Tests
}
