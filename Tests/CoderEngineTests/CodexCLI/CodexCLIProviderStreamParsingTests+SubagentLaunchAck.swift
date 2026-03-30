import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    func testParseStreamJSONEventSubagentLaunchAckSkipsCompletedSyntheticLifecycle() {
        let parsed = runParser(events: [
            [
                "type": "item.updated",
                "item": [
                    "id": "mcp-subagent-ack-1",
                    "call_id": "call-ack-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "arguments": #"{\"task\":\"Review PR\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-subagent-ack-1",
                    "call_id": "call-ack-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "arguments": #"{\"task\":\"Review PR\",\"output\":\"OK — subagent Reviewer launched\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let agentEvents = rawEvents.filter { $0.0 == "agent" }
        let mcpEvents = rawEvents.filter { $0.0 == "mcp_tool_call" }
        let expectedIdentity = SubagentExecutionIdentityBuilder.make(
            role: .reviewer,
            task: "Review PR"
        )

        XCTAssertEqual(mcpEvents.count, 2, "L'ack MCP va mantenuto nel trace tecnico.")
        XCTAssertEqual(agentEvents.count, 1, "L'ack di lancio non deve chiudere il child lifecycle.")
        XCTAssertEqual(agentEvents.first?.1["swarm_id"], expectedIdentity.swarmId)
        XCTAssertEqual(agentEvents.first?.1["status"], "in_progress")
    }

    func testParseStreamJSONEventSubagentFailureStillEmitsTerminalSyntheticLifecycle() {
        let parsed = runParser(events: [
            [
                "type": "item.updated",
                "item": [
                    "id": "mcp-subagent-fail-1",
                    "call_id": "call-fail-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "arguments": #"{\"task\":\"Review PR\"}"#,
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "mcp-subagent-fail-1",
                    "call_id": "call-fail-1",
                    "type": "mcp_tool_call",
                    "tool": "functions.mcp_call",
                    "mcp_tool": "coderide_subagent_reviewer",
                    "status": "failed",
                    "arguments": #"{\"task\":\"Review PR\",\"output\":\"subagent Reviewer launched but child failed\"}"#,
                ],
            ],
        ])

        let rawEvents = parsed.compactMap { event -> (String, [String: String])? in
            if case .raw(let type, let payload) = event { return (type, payload) }
            return nil
        }
        let agentEvents = rawEvents.filter { $0.0 == "agent" }

        XCTAssertEqual(agentEvents.count, 2)
        XCTAssertEqual(agentEvents.last?.1["status"], "failed")
    }
}
