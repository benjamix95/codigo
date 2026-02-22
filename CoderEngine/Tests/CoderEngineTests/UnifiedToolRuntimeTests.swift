import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeTests: XCTestCase {
    func testToolRuntimePolicyStrictDefaults() {
        let policy = ToolRuntimePolicy()
        XCTAssertEqual(policy.maxToolCallsPerRound, 6)
        XCTAssertEqual(policy.maxRepeatedSameToolPerRound, 2)
        XCTAssertEqual(policy.maxBashOutputBytes, 64_000)
        XCTAssertEqual(policy.maxReadBytesPerFile, 128_000)
        XCTAssertFalse(policy.allowDangerousShellPatterns)
        XCTAssertTrue(policy.enableMCP)
        XCTAssertEqual(policy.mcpPerCallTimeoutMs, 20_000)
        XCTAssertEqual(policy.mcpSessionIdleTTLSeconds, 300)
    }

    func testReadValidationFailsWithoutPath() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(id: UUID().uuidString, name: "read", args: [:], sourceProvider: "test", swarmId: nil, scope: .agent)

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testSandboxBlocksOutsideWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codigo-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "x".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: tmp))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "read",
            args: ["path": outsideFile.path],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
    }

    func testBashTimeoutReturnsTimeoutCode() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let policy = ToolRuntimePolicy(timeoutMs: 100)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace), policy: policy)
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "find . -maxdepth 1 >/dev/null; sleep 1"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "timeout")
    }

    func testMCPUnavailableReturnsDeterministicError() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "mcp_call",
            args: ["tool": "nonexistent_tool"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(["mcp_unavailable", "transport"].contains(completed?["error_code"] ?? ""))
    }

    func testReadJSONValidationOnInvalidJSON() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("codigo-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let broken = tmp.appendingPathComponent("broken.json")
        try "{not-json}".write(to: broken, atomically: true, encoding: .utf8)

        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: tmp))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "read_json",
            args: ["path": broken.path],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testMCPListServersAlwaysCompletes() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "mcp_list_servers",
            args: [:],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")
    }

    private func extractLastPayload(_ events: [StreamEvent]) -> [String: String]? {
        for event in events.reversed() {
            if case .raw(_, let payload) = event {
                return payload
            }
        }
        return nil
    }
}
