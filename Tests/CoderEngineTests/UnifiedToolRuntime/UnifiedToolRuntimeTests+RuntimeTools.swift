import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    // MARK: - Bash

    func testShellExecTimeoutTerminatesAndReturnsCoherentError() async {
        let runtime = UnifiedToolRuntime()
        let start = Date()
        let (_, stderr, exitCode) = await runtime.shellExec(
            args: ["/bin/zsh", "-lc", "sleep 2"],
            cwd: FileManager.default.currentDirectoryPath,
            timeout: 100
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(exitCode, 124)
        XCTAssertLessThan(elapsed, 1.5, "shellExec should enforce timeout without waiting full command duration")
        XCTAssertTrue(stderr.contains("Timeout on /bin/zsh"), "Expected coherent timeout error, got: \(stderr)")
    }


    func testShellExecLargeTimeoutDoesNotOverflow() async {
        let runtime = UnifiedToolRuntime()
        let (stdout, stderr, exitCode) = await runtime.shellExec(
            args: ["/bin/echo", "ok"],
            cwd: FileManager.default.currentDirectoryPath,
            timeout: Int.max
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
        XCTAssertEqual(stderr, "")
    }

    func testBashTimeoutReturnsTimeoutCode() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // Use allowDangerousShellPatterns so we can use sleep without strict-mode blocking
        let policy = ToolRuntimePolicy(timeoutMs: 100, allowDangerousShellPatterns: true)
        let ctx = ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: workspace),
            policy: policy
        )
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "sleep 2"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "timeout")
    }


    func testBashStrictModeRejectsEnvPrefixBypass() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "env /bin/sh -c 'echo bypass'"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
        XCTAssertTrue((completed?["detail"] ?? "").contains("Command not allowed in strict mode: env"))
    }

    func testBashValidationFailsEmpty() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "   "],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testBashRejectsWorkspaceDiscoveryViaRipgrep() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "rg --line-number policy App"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue((completed?["detail"] ?? "").contains("coderide_semantic_search"))
        XCTAssertTrue((completed?["detail"] ?? "").contains("coderide_grep"))
    }

    func testBashRejectsWorkspaceDiscoveryViaCommandWrapper() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "command rg --line-number policy App"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue((completed?["detail"] ?? "").contains("Workspace discovery via shell is disabled"))
    }

    // MARK: - MCP

    func testMCPUnavailableReturnsDeterministicError() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "mcp_call", args: ["tool": "nonexistent_tool"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(["mcp_unavailable", "transport"].contains(completed?["error_code"] ?? ""))
    }

    func testMCPListServersAlwaysCompletes() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "mcp_list_servers")
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")
    }

    func testMCPReconnectAcceptsMcpServerAlias() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "mcp_reconnect", args: ["mcp_server": "missing-server"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
    }

    // MARK: - JSON

    func testReadJSONValidationOnInvalidJSON() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let broken = tmp.appendingPathComponent("broken.json")
        try "{not-json}".write(to: broken, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "read_json", args: ["path": broken.path], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    // MARK: - Write Tool

    func testWriteCreatesAndOverwrites() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("new.txt")
        let (call, ctx) = makeCall(
            name: "write",
            args: ["path": file.path, "content": "hello world"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(content, "hello world")
    }

    // MARK: - Event Type Mapping

    func testEventTypeForStrReplace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "let x = 1", "new_string": "let x = 2"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        // str_replace should produce file_change event type
        let hasFileChange = events.contains { event in
            if case .raw(let type, let payload) = event {
                return type == "file_change" && payload["status"] == "completed"
            }
            return false
        }
        XCTAssertTrue(hasFileChange, "str_replace should emit file_change event")
    }

    func testEventTypeForCreateFile() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "create_file",
            args: ["path": tmp.appendingPathComponent("new.txt").path, "content": "hi"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        let hasFileChange = events.contains { event in
            if case .raw(let type, let payload) = event {
                return type == "file_change" && payload["status"] == "completed"
            }
            return false
        }
        XCTAssertTrue(hasFileChange, "create_file should emit file_change event")
    }

    func testSubagentStartEventUsesAgentTypeAndIdentity() async {
        let runtime = UnifiedToolRuntime()
        let call = ToolCall(
            id: UUID().uuidString,
            name: "subagent_explorer",
            args: ["task": "Investigate session cache invalidation"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let payload = await runtime.buildBasePayload(
            call: call,
            normalizedName: "subagent_explorer"
        )
        let eventType = await runtime.startEventTypeForTool(
            name: "subagent_explorer",
            payload: payload
        )
        let expectedIdentity = SubagentExecutionIdentityBuilder.make(
            role: .explorer,
            task: "Investigate session cache invalidation"
        )
        XCTAssertEqual(eventType, "agent")
        XCTAssertEqual(payload["agent_name"], expectedIdentity.agentName)
        XCTAssertEqual(payload["swarm_id"], expectedIdentity.swarmId)
    }

    func testSubagentValidationFailsWithoutTask() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "subagent_explorer",
            args: [:],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue((completed?["detail"] ?? "").contains("'task' is required"))
    }

}
