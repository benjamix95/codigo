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

    func testSyntheticIDEStateEventsFromMCPTodoWriteShorthandIncludesActiveFormAndFiles() {
        let call = ToolCall(
            id: "tc-todo-rich-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "title": "Review changes",
                "status": "in_progress",
                "active_form": "Reviewing changes",
                "linkedFiles": #"["Sources/A.swift","Sources/B.swift"]"#,
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
        let todoPayload = rawEvents["todo_write"]

        XCTAssertEqual(todoPayload?["title"], "Review changes")
        XCTAssertEqual(todoPayload?["activeForm"], "Reviewing changes")
        XCTAssertEqual(todoPayload?["files"], #"["Sources/A.swift","Sources/B.swift"]"#)
    }

    func testSyntheticIDEStateEventsFromMCPTodoWriteEmptyTodosProducesClearMarker() {
        let call = ToolCall(
            id: "tc-todo-clear-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "todos": "[]",
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
        let todoPayload = rawEvents["todo_write"]

        XCTAssertEqual(todoPayload?["title"], "__CODERIDE_CLEAR_TODOS__")
        XCTAssertEqual(todoPayload?["clear_todos"], "true")
        XCTAssertEqual(todoPayload?["todos_json"], "[]")
    }

    func testSyntheticIDEStateEventsFromMCPTodoWriteAcceptsSingleJSONObjectString() {
        let call = ToolCall(
            id: "tc-todo-object-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "todos": #"{"content":"Fix parser","status":"in_progress","activeForm":"Fixing parser"}"#,
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
        let todoPayload = rawEvents["todo_write"]

        XCTAssertEqual(todoPayload?["title"], "Todo updated")
        XCTAssertEqual(
            todoPayload?["todos_json"],
            #"[{"activeForm":"Fixing parser","content":"Fix parser","status":"in_progress"}]"#
        )
    }

    func testSyntheticIDEStateEventsFromMCPTodoWriteAcceptsChecklistString() {
        let call = ToolCall(
            id: "tc-todo-checklist-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
                "todos": """
                - [ ] Inspect parser
                - [~] Apply fix
                - [x] Verify tests
                """,
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
        let todoPayload = rawEvents["todo_write"]

        XCTAssertNotNil(todoPayload)
        if let todosJson = todoPayload?["todos_json"],
           let data = todosJson.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            XCTAssertEqual(array.count, 3)
            XCTAssertEqual(array[0]["content"] as? String, "Inspect parser")
            XCTAssertEqual(array[0]["status"] as? String, "pending")
            XCTAssertEqual(array[1]["status"] as? String, "in_progress")
            XCTAssertEqual(array[2]["status"] as? String, "done")
        } else {
            XCTFail("todos_json should be valid JSON array")
        }
    }

    func testSyntheticIDEStateEventsFromMCPTodoWriteUsesRichArgsTodosArray() {
        let call = ToolCall(
            id: "tc-todo-rich-array-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_todo_write",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent,
            richArgs: [
                "tool": "coderide_todo_write",
                "todos": [
                    [
                        "content": "Investigate",
                        "status": "pending",
                    ],
                    [
                        "content": "Implement",
                        "status": "in_progress",
                    ],
                ],
            ]
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

        XCTAssertEqual(
            rawEvents["todo_write"]?["todos_json"],
            #"[{"content":"Investigate","status":"pending"},{"content":"Implement","status":"in_progress"}]"#
        )
    }

    func testSyntheticIDEStateEventsFromMCPPlanReorderSupportsCamelCaseAliases() {
        let call = ToolCall(
            id: "tc-plan-reorder-1",
            name: "mcp_call",
            args: [
                "tool": "coderide_plan_step_reorder",
                "orderedStepIds": #"["3","1","2"]"#,
                "conversationId": "33333333-3333-3333-3333-333333333333",
            ],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let completedPayload: [String: String] = [
            "status": "completed",
            "is_mcp": "true",
            "mcp_tool": "coderide_plan_step_reorder",
        ]

        let events = UnifiedToolRuntime.syntheticIDEStateEventsFromMCP(
            call: call,
            completedPayload: completedPayload
        )
        let rawEvents = rawEventsByType(events)
        let reorderPayload = rawEvents["plan_step_reorder"]

        XCTAssertEqual(reorderPayload?["ordered_step_ids"], #"["3","1","2"]"#)
        XCTAssertEqual(reorderPayload?["conversation_id"], "33333333-3333-3333-3333-333333333333")
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
