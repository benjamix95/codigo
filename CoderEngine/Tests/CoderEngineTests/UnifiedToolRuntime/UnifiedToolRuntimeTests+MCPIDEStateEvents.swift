import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testSyntheticIDEStateEventsFromMCPTodoWriteProducesTodoWriteEvent() {
        let call = ToolCall(
            id: "tc-todo-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "title": "Aggiornare parser",
                "status": "in_progress",
                "priority": "high",
                "conversation_id": "11111111-1111-1111-1111-111111111111",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let completedPayload: [String: String] = [
            "status": "completed",
            "is_mcp": "true",
            "mcp_tool": "coderide_todo_write",
            "mcp_server": "coderide",
            "tool_call_id": "tc-todo-1",
        ]

        let events = UnifiedToolRuntime.syntheticIDEStateEventsFromMCP(
            call: call,
            completedPayload: completedPayload
        )
        let rawEvents = rawEventsByType(events)
        let todoPayload = rawEvents["todo_write"]

        XCTAssertNotNil(todoPayload)
        XCTAssertEqual(todoPayload?["title"], "Aggiornare parser")
        XCTAssertEqual(todoPayload?["status"], "in_progress")
        XCTAssertEqual(todoPayload?["priority"], "high")
        XCTAssertEqual(todoPayload?["conversation_id"], "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(todoPayload?["mcp_tool"], "coderide_todo_write")
    }

    func testSyntheticIDEStateEventsFromMCPPlanUpsertProducesPlanStepUpsertEvent() {
        let call = ToolCall(
            id: "tc-plan-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_plan_step_upsert",
                "step_id": "2",
                "status": "running",
                "title": "Applicare patch",
                "conversation_id": "22222222-2222-2222-2222-222222222222",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let completedPayload: [String: String] = [
            "status": "completed",
            "is_mcp": "true",
            "mcp_tool": "coderide_plan_step_upsert",
        ]

        let events = UnifiedToolRuntime.syntheticIDEStateEventsFromMCP(
            call: call,
            completedPayload: completedPayload
        )
        let rawEvents = rawEventsByType(events)
        let upsertPayload = rawEvents["plan_step_upsert"]

        XCTAssertNotNil(upsertPayload)
        XCTAssertEqual(upsertPayload?["step_id"], "2")
        XCTAssertEqual(upsertPayload?["status"], "running")
        XCTAssertEqual(upsertPayload?["title"], "Applicare patch")
        XCTAssertEqual(upsertPayload?["conversation_id"], "22222222-2222-2222-2222-222222222222")
    }

    func testSyntheticIDEStateEventsFromMCPFailureProducesValidationError() {
        let call = ToolCall(
            id: "tc-todo-fail",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "title": "Task",
                "status": "done",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let completedPayload: [String: String] = [
            "status": "failed",
            "is_mcp": "true",
            "mcp_tool": "coderide_todo_write",
            "detail": "MCP unavailable",
        ]

        let events = UnifiedToolRuntime.syntheticIDEStateEventsFromMCP(
            call: call,
            completedPayload: completedPayload
        )
        let rawEvents = rawEventsByType(events)

        XCTAssertNil(rawEvents["todo_write"])
        XCTAssertEqual(rawEvents["tool_validation_error"]?["error_code"], "mcp_tool_call_failed")
        XCTAssertEqual(rawEvents["tool_validation_error"]?["tool"], "todo_write")
    }

    func testSyntheticIDEStateEventsFromMCPRejectsInvalidTodosJSON() {
        let call = ToolCall(
            id: "tc-invalid-todos",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "todos": "{bad-json}",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let completedPayload: [String: String] = [
            "status": "completed",
            "is_mcp": "true",
            "mcp_tool": "coderide_todo_write",
        ]

        let events = UnifiedToolRuntime.syntheticIDEStateEventsFromMCP(
            call: call,
            completedPayload: completedPayload
        )
        let rawEvents = rawEventsByType(events)

        XCTAssertNil(rawEvents["todo_write"])
        XCTAssertEqual(rawEvents["tool_validation_error"]?["error_code"], "invalid_todos_payload")
    }

    private func rawEventsByType(_ events: [StreamEvent]) -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            out[type] = payload
        }
        return out
    }
}
