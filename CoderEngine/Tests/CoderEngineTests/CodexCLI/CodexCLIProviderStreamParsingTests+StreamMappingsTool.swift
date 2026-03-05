import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    func testFunctionCallNamespacedSemanticSearchMapsToSemanticSearch() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "sem-1",
                "type": "function_call",
                "name": "functions.semantic_search",
                "arguments": #"{"query":"policy acknowledgment flow"}"#,
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected mapped semantic_search event")
            return
        }

        XCTAssertEqual(parsed.type, "semantic_search")
        XCTAssertEqual(parsed.payload["query"], "policy acknowledgment flow")
        XCTAssertEqual(parsed.payload["status"], "completed")
        XCTAssertEqual(parsed.payload["tool_call_id"], "sem-1")
        XCTAssertEqual(parsed.payload["tool"], "semantic_search")
    }

    func testAgentMessageItemIsNotMappedAsToolEvent() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "msg-1",
                "type": "agent_message",
                "text": "final response",
            ],
        ]

        XCTAssertNil(CodexCLIProvider.parseRawEvent(from: json))
    }

    func testParseStreamJSONEventSynthesizesTodoWriteFromMCPToolCallJSONArguments() {
        let mcpPayload = """
        {"title":"Fix login","status":"in_progress","priority":"high","notes":"critical"}
        """
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-todo",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_todo_write",
                    "arguments": mcpPayload,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let rawTypes = rawEvents.map { $0.0 }
        XCTAssertTrue(rawTypes.contains("mcp_tool_call"))
        XCTAssertTrue(rawTypes.contains("todo_write"))

        let todoPayload = rawEvents.first(where: { $0.0 == "todo_write" })?.1
        XCTAssertEqual(todoPayload?["title"], "Fix login")
        XCTAssertEqual(todoPayload?["status"], "in_progress")
        XCTAssertEqual(todoPayload?["priority"], "high")
        XCTAssertEqual(todoPayload?["notes"], "critical")
    }

    func testParseStreamJSONEventSynthesizesTodoWriteWithActiveFormAndFilesFromShorthand() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-todo-rich",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_todo_write",
                    "arguments": #"{\"title\":\"Review PR\",\"status\":\"in_progress\",\"activeForm\":\"Reviewing PR\",\"linkedFiles\":[\"Sources/A.swift\",\"Sources/B.swift\"]}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let todoPayload = rawEvents.first(where: { $0.0 == "todo_write" })?.1

        XCTAssertEqual(todoPayload?["title"], "Review PR")
        XCTAssertEqual(todoPayload?["status"], "in_progress")
        XCTAssertEqual(todoPayload?["activeForm"], "Reviewing PR")
        let filesValue = todoPayload?["files"]?.replacingOccurrences(of: "\\/", with: "/")
        XCTAssertEqual(filesValue, #"["Sources/A.swift","Sources/B.swift"]"#)
    }

    func testParseStreamJSONEventSynthesizesTodoClearMarkerForEmptyTodosBatch() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-todo-clear",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_todo_write",
                    "arguments": #"{\"todos\":[]}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let todoPayload = rawEvents.first(where: { $0.0 == "todo_write" })?.1

        XCTAssertEqual(todoPayload?["title"], "__CODERIDE_CLEAR_TODOS__")
        XCTAssertEqual(todoPayload?["clear_todos"], "true")
        XCTAssertEqual(todoPayload?["todos_json"], "[]")
    }

    func testParseStreamJSONEventSynthesizesPlanAndSwarmSignalsFromMCPToolCallJSONArguments() {
        let parsed = runParser(events: [
            [
                "type": "item.updated",
                "item": [
                    "id": "mcp-ide-plan",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_step_update",
                    "arguments": #"{\"step_id\":\"2\",\"status\":\"running\",\"title\":\"Implement parser\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-mode",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_activate_plan_mode",
                    "input": #"{\"reason\":\"complex multi-step change\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-panel",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_show_task_panel",
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-ide-swarm-panel",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_show_swarm_panel",
                    "arguments": #"{\"swarm_id\":\"reviewer-1\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        let rawTypes = rawEvents.map { $0.0 }
        XCTAssertEqual(rawTypes.filter { $0 == "mcp_tool_call" }.count, 4)
        XCTAssertEqual(rawTypes.filter { $0 == "plan_step_update" }.count, 1)
        XCTAssertTrue(rawTypes.contains("activate_plan_mode"))
        XCTAssertTrue(rawTypes.contains("coderide_show_task_panel"))
        XCTAssertTrue(rawTypes.contains("coderide_show_swarm_panel"))

        XCTAssertEqual(
            rawEvents.first(where: { $0.0 == "plan_step_update" })?.1["status"],
            "running"
        )
        XCTAssertEqual(
            rawEvents.first(where: { $0.0 == "activate_plan_mode" })?.1["reason"],
            "complex multi-step change"
        )
        XCTAssertEqual(
            rawEvents.first(where: { $0.0 == "coderide_show_swarm_panel" })?.1["swarm_id"],
            "reviewer-1"
        )
    }

    func testParseStreamJSONEventSynthesizesDebugResolvedFromDetailFallback() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-debug-resolve-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_debug_resolve",
                    "arguments": #"{\"detail\":\"Fixed cache race\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertTrue(rawEvents.map(\.0).contains("debug_resolved"))
        XCTAssertEqual(
            rawEvents.first(where: { $0.0 == "debug_resolved" })?.1["summary"],
            "Fixed cache race"
        )
    }

    func testParseStreamJSONEventCarriesMCPMetadataOnPanelSyntheticEvents() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-panel-1",
                    "call_id": "tool-call-42",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "functions.coderide_show_task_panel",
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let panelPayload = rawEvents.first(where: { $0.0 == "coderide_show_task_panel" })?.1
        XCTAssertNotNil(panelPayload)
        XCTAssertEqual(panelPayload?["id"], "mcp-panel-1")
        XCTAssertEqual(panelPayload?["group_id"], "mcp-panel-1")
        XCTAssertEqual(panelPayload?["tool_call_id"], "tool-call-42")
        XCTAssertEqual(panelPayload?["mcp_tool"], "functions.coderide_show_task_panel")
    }

    func testParseStreamJSONEventAllowsNonTerminalDebugSyntheticUpdates() {
        let parsed = runParser(events: [
            [
                "type": "item.updated",
                "item": [
                    "id": "mcp-debug-phase-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_debug_set_phase",
                    "arguments": #"{\"phase\":\"instrumenting\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let debugPayload = rawEvents.first(where: { $0.0 == "debug_phase_update" })?.1
        XCTAssertNotNil(debugPayload)
        XCTAssertEqual(debugPayload?["phase"], "instrumenting")
        XCTAssertEqual(debugPayload?["status"], "in_progress")
    }

    func testParseStreamJSONEventEmitsTodoValidationErrorOnFailedMCPStatus() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-todo-failed-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_todo_write",
                    "status": "failed",
                    "arguments": #"{\"todos\":{\"content\":\"not-array\"}}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertTrue(rawEvents.map(\.0).contains("tool_validation_error"))
        let payload = rawEvents.first(where: { $0.0 == "tool_validation_error" })?.1
        XCTAssertEqual(payload?["error_code"], "invalid_todos_payload")
    }

    func testParseStreamJSONEventSubagentSyntheticUsesDeterministicLifecycle() {
        let parsed = runParser(events: [
            [
                "type": "item.updated",
                "item": [
                    "id": "mcp-subagent-1",
                    "call_id": "call-99",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "arguments": #"{\"task\":\"Review PR\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-subagent-1",
                    "call_id": "call-99",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "arguments": #"{\"task\":\"Review PR\",\"output\":\"Looks good\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let agentEvents = rawEvents.filter { $0.0 == "agent" }
        XCTAssertEqual(agentEvents.count, 2)
        XCTAssertEqual(agentEvents.first?.1["swarm_id"], "reviewer")
        XCTAssertEqual(agentEvents.last?.1["swarm_id"], "reviewer")
        XCTAssertEqual(agentEvents.first?.1["status"], "in_progress")
        XCTAssertEqual(agentEvents.last?.1["status"], "completed")
    }

    func testParseStreamJSONEventNormalizesMCPNamespaceWrappedIDEStateTool() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-panel-ns-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "functions.mcp__coderide__coderide_show_task_panel",
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        XCTAssertTrue(rawEvents.map(\.0).contains("coderide_show_task_panel"))
    }

    func testParseStreamJSONEventDoesNotEmitTodoWriteOnFailedStatusWithValidPayload() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-todo-failed-2",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_todo_write",
                    "status": "failed",
                    "arguments": #"{\"title\":\"Sync store\",\"status\":\"in_progress\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertFalse(rawEvents.map(\.0).contains("todo_write"))
        let validationPayload = rawEvents.first(where: { $0.0 == "tool_validation_error" })?.1
        XCTAssertNotNil(validationPayload)
        XCTAssertEqual(validationPayload?["error_code"], "mcp_tool_call_failed")
        XCTAssertEqual(validationPayload?["tool"], "todo_write")
    }

    func testParseStreamJSONEventDoesNotEmitPlanCreateOnFailedStatus() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-failed-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_create",
                    "status": "failed",
                    "arguments": #"{\"goal\":\"Plan X\",\"steps\":[{\"step_id\":\"1\",\"status\":\"pending\"}]}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertFalse(rawEvents.map(\.0).contains("plan_create"))
        let validationPayload = rawEvents.first(where: { $0.0 == "tool_validation_error" })?.1
        XCTAssertNotNil(validationPayload)
        XCTAssertEqual(validationPayload?["error_code"], "mcp_tool_call_failed")
        XCTAssertEqual(validationPayload?["tool"], "plan_create")
    }
}
