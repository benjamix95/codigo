import Foundation
import XCTest
@testable import CoderEngine

extension ProviderToolEventMapperTests {
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

    func testTodoWriteWithEmptyTodosArrayEmitsClearMarker() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "TodoWrite",
            payload: ["todos": [] as [[String: Any]]]
        )
        XCTAssertEqual(mapped?.type, "todo_write")
        XCTAssertEqual(mapped?.payload["title"], "__CODERIDE_CLEAR_TODOS__")
        XCTAssertEqual(mapped?.payload["clear_todos"], "true")
        XCTAssertEqual(mapped?.payload["todos_json"], "[]")
    }

    func testTodoWriteWithEmptyTodosJSONStringEmitsClearMarker() {
        let mapped = ProviderToolEventMapper.map(
            toolName: "TodoWrite",
            payload: ["todos": "[]"]
        )
        XCTAssertEqual(mapped?.type, "todo_write")
        XCTAssertEqual(mapped?.payload["title"], "__CODERIDE_CLEAR_TODOS__")
        XCTAssertEqual(mapped?.payload["clear_todos"], "true")
        XCTAssertEqual(mapped?.payload["todos_json"], "[]")
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
