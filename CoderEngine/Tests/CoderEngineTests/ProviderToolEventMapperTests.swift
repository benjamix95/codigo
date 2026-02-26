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
        XCTAssertEqual(mapped?.type, "todo_write")
        XCTAssertTrue((mapped?.payload["title"] ?? "").contains("Read todo"))
    }
}
