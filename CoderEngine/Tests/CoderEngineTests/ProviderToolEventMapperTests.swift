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

    func testApplyPatchMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.apply_patch",
            payload: [
                "path": "Sources/CoderIDE/MessageToolTraceView.swift",
                "patch": """
                @@ -1 +1 @@
                -old
                +new
                """,
            ]
        )

        XCTAssertEqual(mapped?.type, "file_change")
        XCTAssertEqual(mapped?.payload["tool"], "apply_patch")
        XCTAssertEqual(mapped?.payload["path"], "Sources/CoderIDE/MessageToolTraceView.swift")
        XCTAssertNotNil(mapped?.payload["diffPreview"])
    }

    // MARK: - Claude CLI Native Tool Name Tests

    func testClaudeCLIReadMapsToReadBatchCompleted() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Read",
            payload: ["file_path": "/Users/dev/project/main.swift"]
        )
        XCTAssertEqual(mapped?.type, "read_batch_completed")
        XCTAssertEqual(mapped?.payload["path"], "/Users/dev/project/main.swift")
    }

    func testClaudeCLIEditMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Edit",
            payload: [
                "file_path": "Sources/App.swift",
                "old_string": "let x = 1",
                "new_string": "let x = 2",
            ]
        )
        XCTAssertEqual(mapped?.type, "file_change")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Edited"))
    }

    func testClaudeCLIWriteMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Write",
            payload: [
                "file_path": "NewFile.swift",
                "content": "import Foundation",
            ]
        )
        XCTAssertEqual(mapped?.type, "file_change")
    }

    func testClaudeCLIBashMapsToCommandExecution() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Bash",
            payload: ["command": "git status"]
        )
        XCTAssertEqual(mapped?.type, "command_execution")
        XCTAssertEqual(mapped?.payload["command"], "git status")
    }

    func testClaudeCLIGrepMapsToSearch() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Grep",
            payload: [
                "pattern": "TODO",
                "path": "Sources/",
            ]
        )
        XCTAssertEqual(mapped?.type, "instant_grep")
    }

    func testClaudeCLIGlobMapsToSearch() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Glob",
            payload: ["pattern": "**/*.swift"]
        )
        // Glob maps to search since it has a pattern (query-like)
        XCTAssertNotNil(mapped)
        let type = mapped?.type ?? ""
        XCTAssertTrue(type == "instant_grep" || type == "search",
                      "Expected search-type event but got \(type)")
    }

    func testNotebookEditMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "NotebookEdit",
            payload: [
                "path": "analysis.ipynb",
                "cell_number": 3,
                "new_source": "print('hello')",
            ] as [String: Any]
        )
        XCTAssertEqual(mapped?.type, "file_change")
        XCTAssertEqual(mapped?.payload["tool"], "notebook_edit")
    }

    func testWriteFileMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "write_file",
            payload: [
                "path": "output.txt",
                "content": "Hello World",
            ]
        )
        XCTAssertEqual(mapped?.type, "file_change")
    }

    func testNotebookWriteMapsToFileChange() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "notebook_write",
            payload: [
                "path": "notebook.ipynb",
                "content": "{}",
            ]
        )
        XCTAssertEqual(mapped?.type, "file_change")
    }

    // MARK: - Semantic Search

    func testSemanticSearchMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "semantic_search",
            payload: [
                "query": "where is authentication handled",
            ]
        )
        XCTAssertEqual(mapped?.type, "semantic_search")
        XCTAssertEqual(mapped?.payload["query"], "where is authentication handled")
    }

    func testCodebaseSearchMapsToSemantic() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "codebase_search",
            payload: [
                "query": "ChatPanelView",
                "kind": "class",
            ]
        )
        XCTAssertEqual(mapped?.type, "semantic_search")
    }

    // MARK: - Web Tools

    func testWebSearchMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "web_search",
            payload: ["query": "Swift concurrency"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertTrue(mapped?.type.hasPrefix("web_search") ?? false)
    }

    func testWebFetchMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "web_fetch",
            payload: ["url": "https://example.com"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertTrue(mapped?.type.hasPrefix("web_fetch") ?? false)
    }

    func testDebugSetPhaseMapsToTypedDebugPhaseEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_set_phase",
            payload: [
                "phase": "fixing",
                "detail": "Applying patch"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_phase_update")
        XCTAssertEqual(mapped?.payload["phase"], "fixing")
        XCTAssertEqual(mapped?.payload["detail"], "Applying patch")
    }

    func testDebugRequestUserMapsToTypedRequestEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_request_user",
            payload: [
                "kind": "question",
                "prompt": "Can you reproduce this?"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_user_request")
        XCTAssertEqual(mapped?.payload["kind"], "question")
        XCTAssertEqual(mapped?.payload["prompt"], "Can you reproduce this?")
    }

    func testDebugResolveUsesDetailFallbackWhenSummaryMissing() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_resolve",
            payload: [
                "detail": "Fixed race condition in cache invalidation"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_resolved")
        XCTAssertEqual(mapped?.payload["summary"], "Fixed race condition in cache invalidation")
    }

    func testDebugLogMapsToTypedDebugLogEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_log",
            payload: [
                "severity": "info",
                "source": "Runtime",
                "message": "Boot complete",
                "status": "completed"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_log")
        XCTAssertEqual(mapped?.payload["message"], "Boot complete")
        XCTAssertEqual(mapped?.payload["tool"], "debug_log")
    }

    func testDebugSessionMapsToTypedDebugSessionEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_session",
            payload: [
                "action": "start",
                "detail": "session opened",
                "status": "completed"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_session")
        XCTAssertEqual(mapped?.payload["action"], "start")
        XCTAssertEqual(mapped?.payload["tool"], "debug_session")
    }

    func testDebugCleanMapsToTypedDebugCleanEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_clean",
            payload: [
                "dry_run": "true",
                "detail": "Preview",
                "status": "preview"
            ]
        )

        XCTAssertEqual(mapped?.type, "debug_clean")
        XCTAssertEqual(mapped?.payload["dry_run"], "true")
        XCTAssertEqual(mapped?.payload["status"], "preview")
    }

    func testMCPCallCoderideActivatePlanModeMapsToActivatePlanMode() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "functions.mcp_call",
            payload: [
                "mcp_server": "coderide",
                "mcp_tool": "coderide_activate_plan_mode",
                "arguments": #"{\"reason\":\"User requested explicit planning mode\"}"#
            ]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "User requested explicit planning mode")
    }

    func testNamespacedActivatePlanModeMapsToActivatePlanMode() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_activate_plan_mode",
            payload: ["reason": "Manual activation"]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "Manual activation")
    }

    func testAskUserQuestionAliasMapsQuestionToPlanReason() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "ask_user_question",
            payload: ["question": "Do you prefer SwiftUI or UIKit?"]
        )

        XCTAssertEqual(mapped?.type, "activate_plan_mode")
        XCTAssertEqual(mapped?.payload["reason"], "Do you prefer SwiftUI or UIKit?")
    }

    func testLegacyDebugPanelMapsToValidationError() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_debug_panel",
            payload: [
                "action": "open",
                "phase": "describing"
            ]
        )

        XCTAssertEqual(mapped?.type, "tool_validation_error")
        XCTAssertEqual(mapped?.payload["error_code"], "legacy_debug_panel_removed")
    }

    func testShowSwarmPanelMapsToIDEEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "coderide_show_swarm_panel",
            payload: ["swarm_id": "reviewer-1"]
        )

        XCTAssertEqual(mapped?.type, "coderide_show_swarm_panel")
        XCTAssertEqual(mapped?.payload["swarm_id"], "reviewer-1")
    }

    // MARK: - Skill Tool

    func testSkillToolMapsToSkillInvocation() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "Skill",
            payload: ["skill": "commit", "args": "-m 'fix bug'"]
        )
        XCTAssertEqual(mapped?.type, "skill_invocation")
        XCTAssertEqual(mapped?.payload["skill"], "commit")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Skill"))
    }

    func testSkillToolLowercaseMapsToSkillInvocation() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "skill",
            payload: ["skill": "review-pr", "args": "123"]
        )
        XCTAssertEqual(mapped?.type, "skill_invocation")
        XCTAssertEqual(mapped?.payload["skill"], "review-pr")
    }

    // MARK: - TodoWrite Tool

    func testTodoWriteMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "TodoWrite",
            payload: ["title": "Fix authentication bug", "status": "pending"]
        )
        XCTAssertEqual(mapped?.type, "todo_write")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Todo"))
    }

    func testTodoWriteWithTodosArrayMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "TodoWrite",
            payload: [
                "todos": [
                    ["content": "Fix auth bug", "status": "in_progress", "activeForm": "Fixing auth bug"],
                    ["content": "Update tests", "status": "pending", "activeForm": "Updating tests"],
                    ["content": "Run build", "status": "pending", "activeForm": "Running build"],
                ] as [[String: Any]]
            ]
        )
        XCTAssertEqual(mapped?.type, "todo_write")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Fix auth bug"), "Title should use first todo item content")
        XCTAssertEqual(mapped?.payload["count"], "3")
        XCTAssertNotNil(mapped?.payload["todos_json"], "Should serialize todos array as JSON")

        // Verify the JSON is valid and contains all items
        if let todosJson = mapped?.payload["todos_json"],
           let data = todosJson.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            XCTAssertEqual(array.count, 3)
            XCTAssertEqual(array[0]["content"] as? String, "Fix auth bug")
            XCTAssertEqual(array[1]["content"] as? String, "Update tests")
            XCTAssertEqual(array[2]["content"] as? String, "Run build")
        } else {
            XCTFail("todos_json should be valid JSON array")
        }
    }

    func testTodoWriteWithEmptyTodosArrayFallsBack() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "TodoWrite",
            payload: ["todos": [] as [[String: Any]]]
        )
        XCTAssertEqual(mapped?.type, "todo_write")
        // Empty array falls back to "Update todo list"
        XCTAssertEqual(mapped?.payload["title"], "Update todo list")
        XCTAssertNil(mapped?.payload["todos_json"])
    }

    func testTodoReadMapsCorrectly() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "todo_read",
            payload: [:]
        )
        XCTAssertEqual(mapped?.type, "todo_read")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Read todo"))
    }

    func testSubagentExplorerMapsToAgentEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "subagent_explorer",
            payload: ["task": "Find authentication code"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertNotEqual(mapped?.type, "command_execution",
                          "subagent_explorer should NOT fall back to command_execution")
    }

    func testSubagentCoderMapsToAgentEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "subagent_coder",
            payload: ["task": "Implement feature"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertNotEqual(mapped?.type, "command_execution",
                          "subagent_coder should NOT fall back to command_execution")
    }

    func testSubagentDebuggerMapsToAgentEvent() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "subagent_debugger",
            payload: ["task": "Debug crash"]
        )
        XCTAssertNotNil(mapped)
        XCTAssertNotEqual(mapped?.type, "command_execution",
                          "subagent_debugger should NOT fall back to command_execution")
    }

    func testSubagentTestWriterInjectsSwarmMetadataFromToolNameWhenPayloadHasNoRole() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "subagent_testWriter",
            payload: ["task": "Write regression tests"]
        )

        XCTAssertEqual(mapped?.type, "agent")
        XCTAssertEqual(mapped?.payload["tool"], "subagent_testwriter")
        XCTAssertEqual(mapped?.payload["swarm_id"], "testWriter")
        XCTAssertEqual(mapped?.payload["group_id"], "swarm-testWriter")
    }
}
