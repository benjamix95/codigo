import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    func testParseStreamJSONEventSynthesizesPlanLifecycleEventsFromMCPToolCalls() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-create-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_create",
                    "arguments": #"{\"goal\":\"Plan v2\",\"steps\":[{\"step_id\":\"1\",\"status\":\"pending\"}],\"conversation_id\":\"11111111-1111-1111-1111-111111111111\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-upsert-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_step_upsert",
                    "arguments": #"{\"step_id\":\"1\",\"status\":\"running\",\"title\":\"Analisi\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-walkthrough-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_set_walkthrough",
                    "arguments": "{\"markdown\":\"## Done\",\"summary\":\"Completato\",\"outcome\":\"done\"}",
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-questions-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_request_user_input",
                    "arguments": #"{\"title\":\"Clarify scope\",\"questions\":[{\"prompt\":\"Target?\",\"options\":[{\"label\":\"iOS\"},{\"label\":\"macOS\"}]}]}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_create"))
        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_step_upsert"))
        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_set_walkthrough"))
        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_request_user_input"))

        let createPayload = rawEvents.first(where: { $0.0 == "plan_create" })?.1
        XCTAssertEqual(createPayload?["goal"], "Plan v2")
        XCTAssertNotNil(createPayload?["steps"])

        let upsertPayload = rawEvents.first(where: { $0.0 == "plan_step_upsert" })?.1
        XCTAssertEqual(upsertPayload?["step_id"], "1")
        XCTAssertEqual(upsertPayload?["status"], "running")

        let questionsPayload = rawEvents.first(where: { $0.0 == "plan_request_user_input" })?.1
        XCTAssertEqual(questionsPayload?["title"], "Clarify scope")
        XCTAssertTrue(questionsPayload?["questions"]?.contains("Target?") == true)
    }

    func testParseStreamJSONEventSynthesizesPlanBatchAndDiffEvents() {
        let parsed = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-batch-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_step_batch_update",
                    "arguments": #"{\"updates\":[{\"step_id\":\"1\",\"status\":\"done\"},{\"step_id\":\"2\",\"status\":\"running\"}]}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-plan-diff-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_plan_diff",
                    "arguments": #"{\"from_snapshot_id\":\"snap-a\",\"to_snapshot_id\":\"snap-b\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }

        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_step_batch_update"))
        XCTAssertTrue(rawEvents.map { $0.0 }.contains("plan_diff"))

        let batchPayload = rawEvents.first(where: { $0.0 == "plan_step_batch_update" })?.1
        XCTAssertNotNil(batchPayload?["updates"])
        XCTAssertTrue(batchPayload?["updates"]?.contains("\"step_id\":\"1\"") == true)

        let diffPayload = rawEvents.first(where: { $0.0 == "plan_diff" })?.1
        XCTAssertEqual(diffPayload?["from_snapshot_id"], "snap-a")
        XCTAssertEqual(diffPayload?["to_snapshot_id"], "snap-b")
    }
}
