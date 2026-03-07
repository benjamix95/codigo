import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testReadRangeConsumesRoundBudget() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("BudgetRead.swift")
        try """
        line one
        line two
        line three
        line four
        """.write(to: file, atomically: true, encoding: .utf8)

        let policy = ToolRuntimePolicy(maxToolCallsPerRound: 1)
        let context = ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: tmp),
            policy: policy
        )

        let firstCall = ToolCall(
            id: UUID().uuidString,
            name: "read_range",
            args: ["path": file.path, "start": "1", "end": "2"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let secondCall = ToolCall(
            id: UUID().uuidString,
            name: "read_range",
            args: ["path": file.path, "start": "3", "end": "4"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let firstEvents = await runtime.execute(firstCall, context: context)
        let secondEvents = await runtime.execute(secondCall, context: context)

        XCTAssertEqual(extractLastPayload(firstEvents)?["status"], "completed")
        XCTAssertEqual(extractLastPayload(secondEvents)?["status"], "failed")
        XCTAssertEqual(extractLastPayload(secondEvents)?["error_code"], "budget_exceeded")
    }
}
