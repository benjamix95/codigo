import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeMCPConsistencyTests: XCTestCase {
    private func makeLocalContext(
        workspace: URL
    ) -> ToolExecutionContext {
        ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: workspace),
            policy: ToolRuntimePolicy(enableMCP: false)
        )
    }

    private func makeTmpWorkspace() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("solocode-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func extractLastPayload(_ events: [StreamEvent]) -> [String: String]? {
        for event in events.reversed() {
            if case .raw(_, let payload) = event {
                return payload
            }
        }
        return nil
    }

    private func extractPayload(
        _ events: [StreamEvent],
        matchingTool toolName: String
    ) -> [String: String]? {
        for event in events.reversed() {
            guard case .raw(_, let payload) = event else { continue }
            if payload["tool"] == toolName {
                return payload
            }
        }
        return nil
    }

    private func rawTypes(_ events: [StreamEvent]) -> [String] {
        events.compactMap { event in
            if case .raw(let type, _) = event { return type }
            return nil
        }
    }

    private func makeCall(
        name: String,
        args: [String: String] = [:],
        workspace: URL
    ) -> (ToolCall, ToolExecutionContext) {
        let call = ToolCall(
            id: UUID().uuidString,
            name: name,
            args: args,
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        return (call, ctx)
    }

    private func registerCoderideAlias(_ toolName: String) {
        let descriptor = MCPToolDescriptor(
            name: "coderide_\(toolName)",
            description: "\(toolName) via coderide",
            schema: #"{"type":"object","properties":{}}"#,
            serverId: "missing-server",
            serverName: "coderide"
        )
        XCTAssertTrue(MCPNativeToolRegistry.shared.mergeRegister(tools: [descriptor]))
    }

    private func assertCanonicalToolPrefersCoderideAlias(
        canonicalName: String,
        args: [String: String],
        expectedMCPTool: String,
        workspace: URL,
        line: UInt = #line
    ) async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: canonicalName, args: args, workspace: workspace)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed", line: line)
        XCTAssertEqual(completed?["tool"], canonicalName, line: line)
        XCTAssertEqual(completed?["is_mcp"], "true", line: line)
        XCTAssertEqual(completed?["mcp_tool"], expectedMCPTool, line: line)
    }

    private func assertCanonicalIDEStateToolPreservesMCPMarkers(
        canonicalName: String,
        args: [String: String] = [:],
        expectedMCPTool: String,
        workspace: URL,
        line: UInt = #line
    ) async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: canonicalName, args: args, workspace: workspace)
        let events = await runtime.execute(call, context: ctx)
        let payload = extractPayload(events, matchingTool: canonicalName)

        XCTAssertEqual(payload?["tool"], canonicalName, line: line)
        XCTAssertEqual(payload?["is_mcp"], "true", line: line)
        XCTAssertEqual(payload?["mcp_tool"], expectedMCPTool, line: line)
    }

    func testGrepValidationMentionsPatternOrQueryAlias() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, _) = makeCall(name: "grep", workspace: tmp)
        let events = await runtime.execute(call, context: makeLocalContext(workspace: tmp))
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        let message = completed?["detail"] ?? completed?["output"] ?? ""
        XCTAssertTrue(message.contains("pattern (or query) is required"))
        XCTAssertFalse(rawTypes(events).contains("mcp_tool_call"))
    }

    func testDefaultRuntimeReusesSharedMCPSessionManager() async {
        let runtimeA = UnifiedToolRuntime()
        let runtimeB = UnifiedToolRuntime()
        let managerA = await runtimeA.mcpSessions
        let managerB = await runtimeB.mcpSessions

        XCTAssertEqual(
            ObjectIdentifier(managerA),
            ObjectIdentifier(MCPSessionManager.shared)
        )
        XCTAssertEqual(
            ObjectIdentifier(managerB),
            ObjectIdentifier(MCPSessionManager.shared)
        )
    }

    func testFindFilesSupportsPathScopeAlias() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let scopeA = tmp.appendingPathComponent("ScopeA", isDirectory: true)
        let scopeB = tmp.appendingPathComponent("ScopeB", isDirectory: true)
        try FileManager.default.createDirectory(at: scopeA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scopeB, withIntermediateDirectories: true)

        try "struct ScopeAFile {}".write(
            to: scopeA.appendingPathComponent("ScopedMatch.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct ScopeBFile {}".write(
            to: scopeB.appendingPathComponent("ScopedMatch.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, _) = makeCall(
            name: "find_files",
            args: ["pattern": "ScopedMatch.swift", "path": "ScopeA"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: makeLocalContext(workspace: tmp))
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("ScopeA/ScopedMatch.swift"), "Output find_files inatteso: \(output)")
        XCTAssertFalse(output.contains("ScopeB/ScopedMatch.swift"), "Output find_files inatteso: \(output)")
    }

    func testCodebaseSearchSupportsPathScopeAlias() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let scopeA = tmp.appendingPathComponent("ScopeA", isDirectory: true)
        let scopeB = tmp.appendingPathComponent("ScopeB", isDirectory: true)
        try FileManager.default.createDirectory(at: scopeA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scopeB, withIntermediateDirectories: true)

        try "struct SharedScopedSymbol {}".write(
            to: scopeA.appendingPathComponent("ScopedSymbol.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct SharedScopedSymbol {}".write(
            to: scopeB.appendingPathComponent("ScopedSymbol.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, _) = makeCall(
            name: "codebase_search",
            args: ["query": "SharedScopedSymbol", "path": "ScopeA"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: makeLocalContext(workspace: tmp))
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("ScopeA/ScopedSymbol.swift"), "Output codebase_search inatteso: \(output)")
        XCTAssertFalse(output.contains("ScopeB/ScopedSymbol.swift"), "Output codebase_search inatteso: \(output)")
    }

    func testMCPInvocationRejectsConflictingServerAliases() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "mcp_call",
            args: [
                "tool": "server-a/tool-x",
                "server_id": "server-b"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertEqual(completed?["is_mcp"], "true")
    }

    func testAmbiguousQualifiedToolNameDoesNotFallbackToMCP() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "server/tool/extra", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertNil(completed?["is_mcp"])
    }

    func testMCPReadResourcePreservesMCPUnavailableErrorCode() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "mcp_read_resource",
            args: [
                "server": "missing-server",
                "uri": "resource://missing"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
        XCTAssertEqual(completed?["is_mcp"], "true")
    }

    func testMCPGetPromptPreservesMCPUnavailableErrorCode() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "mcp_get_prompt",
            args: [
                "server": "missing-server",
                "name": "missing_prompt"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
        XCTAssertEqual(completed?["is_mcp"], "true")
    }

    func testMCPSubscribeRejectsInvalidAction() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "mcp_subscribe",
            args: [
                "server": "missing-server",
                "uri": "resource://missing",
                "action": "pause"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertEqual(completed?["is_mcp"], "true")
    }

    func testMCPLogsRejectsInvalidAction() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "mcp_logs",
            args: [
                "action": "tail"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertEqual(completed?["is_mcp"], "true")
    }

    func testCanonicalReadPrefersCoderideAliasWhenRegistryIsWarm() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "coderide_read",
            description: "read file",
            schema: #"{"type":"object","properties":{"path":{"type":"string"}}}"#,
            serverId: "missing-server",
            serverName: "coderide"
        )
        XCTAssertTrue(registry.register(tools: [descriptor]))

        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("Sample.swift")
        try "let value = 42\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "read",
            args: ["path": file.path],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["tool"], "read")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_read")
    }

    func testCanonicalReviewStartPrefersCoderideAliasWhenRegistryIsWarm() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        registerCoderideAlias("review_start")

        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "review_start", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractPayload(events, matchingTool: "review_start")

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["tool"], "review_start")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_review_start")
    }

    func testCanonicalWebSearchPrefersCoderideAliasWhenRegistryIsWarm() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let descriptor = MCPToolDescriptor(
            name: "coderide_web_search",
            description: "web search",
            schema: #"{"type":"object","properties":{"query":{"type":"string"}}}"#,
            serverId: "missing-server",
            serverName: "coderide"
        )
        XCTAssertTrue(registry.register(tools: [descriptor]))

        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "web_search",
            args: ["query": "coderide transport closed"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["tool"], "web_search")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_web_search")
    }

    func testCanonicalToolFamiliesPreferCoderideAliasesWhenRegistryIsWarm() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        for alias in ["write", "grep", "todo_write", "plan_create", "debug_session"] {
            registerCoderideAlias(alias)
        }

        await assertCanonicalToolPrefersCoderideAlias(
            canonicalName: "write",
            args: ["path": tmp.appendingPathComponent("Output.txt").path, "content": "ciao"],
            expectedMCPTool: "coderide_write",
            workspace: tmp
        )
        await assertCanonicalToolPrefersCoderideAlias(
            canonicalName: "grep",
            args: ["pattern": "needle"],
            expectedMCPTool: "coderide_grep",
            workspace: tmp
        )
        let todoRuntime = UnifiedToolRuntime()
        let (todoCall, todoContext) = makeCall(name: "todo_write", args: ["todos": "[]"], workspace: tmp)
        let todoEvents = await todoRuntime.execute(todoCall, context: todoContext)
        let todoPayload = extractPayload(todoEvents, matchingTool: "todo_write")
        XCTAssertEqual(todoPayload?["is_mcp"], "true")
        XCTAssertEqual(todoPayload?["mcp_tool"], "coderide_todo_write")

        let planRuntime = UnifiedToolRuntime()
        let (planCall, planContext) = makeCall(name: "plan_create", args: ["goal": "stabilizzare coderide"], workspace: tmp)
        let planEvents = await planRuntime.execute(planCall, context: planContext)
        let planPayload = extractPayload(planEvents, matchingTool: "plan_create")
        XCTAssertEqual(planPayload?["is_mcp"], "true")
        XCTAssertEqual(planPayload?["mcp_tool"], "coderide_plan_create")

        await assertCanonicalToolPrefersCoderideAlias(
            canonicalName: "debug_session",
            args: ["action": "start"],
            expectedMCPTool: "coderide_debug_session",
            workspace: tmp
        )
    }

    func testCanonicalReviewSecurityBugHunterReadOnlyToolsPreserveMCPMarkers() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        for alias in [
            "review_status",
            "review_findings",
            "review_get_outcome",
            "security_status",
            "security_findings",
            "bughunter_status",
            "bughunter_findings",
            "bughunter_run_history",
            "bughunter_explain_cluster",
        ] {
            registerCoderideAlias(alias)
        }

        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "review_status",
            expectedMCPTool: "coderide_review_status",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "review_findings",
            args: ["limit": "10"],
            expectedMCPTool: "coderide_review_findings",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "review_get_outcome",
            expectedMCPTool: "coderide_review_get_outcome",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "security_status",
            expectedMCPTool: "coderide_security_status",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "security_findings",
            args: ["limit": "10"],
            expectedMCPTool: "coderide_security_findings",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "bughunter_status",
            expectedMCPTool: "coderide_bughunter_status",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "bughunter_findings",
            args: ["limit": "10"],
            expectedMCPTool: "coderide_bughunter_findings",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "bughunter_run_history",
            expectedMCPTool: "coderide_bughunter_run_history",
            workspace: tmp
        )
        await assertCanonicalIDEStateToolPreservesMCPMarkers(
            canonicalName: "bughunter_explain_cluster",
            expectedMCPTool: "coderide_bughunter_explain_cluster",
            workspace: tmp
        )
    }

    func testRustPreferredCanonicalToolFailsClosedWhenRegistryIsWarmButAliasIsMissing() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        registerCoderideAlias("read")

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(
            name: "grep",
            args: ["pattern": "needle"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_grep")
    }

    func testSessionScopedCanonicalReviewToolFailsExplicitlyWhenCurrentSessionDoesNotExposeIt() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "review_start", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractPayload(events, matchingTool: "review_start")
        let message = completed?["detail"] ?? completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_review_start")
        XCTAssertTrue(message.contains("does not expose required tool 'coderide_review_start'"))
    }

    func testSessionScopedCanonicalPlanToolFailsExplicitlyWhenCurrentSessionDoesNotExposeIt() async throws {
        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "plan_create", args: ["goal": "align runtime"], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractPayload(events, matchingTool: "plan_create")
        let message = completed?["detail"] ?? completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "mcp_unavailable")
        XCTAssertEqual(completed?["is_mcp"], "true")
        XCTAssertEqual(completed?["mcp_tool"], "coderide_plan_create")
        XCTAssertTrue(message.contains("does not expose required tool 'coderide_plan_create'"))
    }
}
