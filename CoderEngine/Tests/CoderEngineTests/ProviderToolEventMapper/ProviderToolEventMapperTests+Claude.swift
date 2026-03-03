import Foundation
import XCTest
@testable import CoderEngine

extension ProviderToolEventMapperTests {
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

}
