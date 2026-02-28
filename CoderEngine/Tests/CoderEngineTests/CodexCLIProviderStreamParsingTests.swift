import XCTest
@testable import CoderEngine

final class CodexCLIProviderStreamParsingTests: XCTestCase {
    func testParseStreamJSONPayloadsRemovesControlPrefix() {
        let raw = "\u{04}\u{08}\u{08}{\"type\":\"turn.started\"}"
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.started")
    }

    func testParseStreamJSONPayloadsExtractsJSONFromNoisyLine() {
        let raw = "2026-01-01T00:00:00Z WARN something {\"type\":\"turn.completed\"}"
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.completed")
    }

    func testParseStreamJSONPayloadsHandlesConcatenatedObjects() {
        let raw = #"{"type":"turn.started"}{"type":"turn.completed"}"#
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.started")
        XCTAssertEqual(payloads.last?["type"] as? String, "turn.completed")
    }

    func testReasoningAndAgentMessageRemainSeparated() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Evaluating the best approach"
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-1",
                    "type": "agent_message",
                    "text": "Clean final answer"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let assistantText = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }.joined()

        let rawTurnEvents = events.compactMap { event -> String? in
            if case .raw(let type, _) = event, type == "turn_started" || type == "turn_completed" {
                return type
            }
            return nil
        }

        let rawReasoningEvents = events.compactMap { event -> String? in
            if case .raw(let type, _) = event, type == "reasoning" {
                return type
            }
            return nil
        }
        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(assistantText, "Clean final answer")
        XCTAssertFalse(assistantText.contains("best approach"))
        XCTAssertEqual(rawReasoningEvents.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["title"], "Reasoning")
        XCTAssertEqual(reasoningPayloads.first?["output"], "Evaluating the best approach")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "reasoning-1")
        XCTAssertEqual(rawTurnEvents, ["turn_started", "turn_completed"])
    }

    func testReasoningUsesSwarmGroupIdWhenSwarmIdPresent() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-1",
                    "type": "reasoning",
                    "swarm_id": "s-arch",
                    "text": "Coalescing stream updates for stable grouping"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "s-arch")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-arch")
    }

    func testReasoningTrimmedSwarmIdGetsCanonicalGroupId() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-2",
                    "type": "reasoning",
                    "swarm_id": "  s-ops  ",
                    "text": "Trimming is expected before group assignment"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "s-ops")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-ops")
    }

    func testReasoningSkipsDoubleSwarmPrefixInGroupId() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-3",
                    "type": "reasoning",
                    "swarm_id": "swarm-s-prefixed",
                    "text": "Prefixed swarm IDs should remain single-prefixed"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "swarm-s-prefixed")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-prefixed")
    }

    func testReasoningUpdatesAreNotDedupedWhenOutputGrows() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.updated",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Step 1"
                ],
            ],
            [
                "type": "item.updated",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Step 1\nStep 2"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 2)
        XCTAssertEqual(reasoningPayloads.first?["output"], "Step 1")
        XCTAssertEqual(reasoningPayloads.last?["output"], "Step 1\nStep 2")
    }

    func testCommandExecutionEmitsStartedAndCompletedStatuses() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.started",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la"
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la",
                    "output": "ok"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let statuses = events.compactMap { event -> String? in
            if case .raw(let type, let payload) = event, type == "command_execution" {
                return payload["status"]
            }
            return nil
        }

        XCTAssertEqual(statuses, ["started", "completed"])
    }

    func testParserNormalizesEventTypesWithEmbeddedWhitespace() {
        let events = runParser(events: [
            ["type": "turn. started"],
            [
                "type": "item. started",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la"
                ],
            ],
            [
                "type": "item. completed",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la",
                    "output": "ok"
                ],
            ],
            ["type": "turn. completed"],
        ])

        let timelineTypes = events.compactMap { event -> String? in
            if case .raw(let type, _) = event { return type }
            return nil
        }

        XCTAssertTrue(timelineTypes.contains("turn_started"))
        XCTAssertTrue(timelineTypes.contains("turn_completed"))
        XCTAssertEqual(
            timelineTypes.filter { $0 == "command_execution" }.count,
            2
        )
    }

    func testTurnWithCompletedAgentMessageStillProducesFinalText() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-final",
                    "type": "agent_message",
                    "text": "Final output even without intermediate deltas"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let assistantDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertEqual(assistantDeltas, ["Final output even without intermediate deltas"])
    }

    func testRawDedupKeyDiffersWhenPayloadChangesWithSameIdentifierAndStatus() {
        let base: [String: String] = [
            "id": "cmd-1",
            "status": "started",
            "output": "line-1"
        ]
        let changed: [String: String] = [
            "id": "cmd-1",
            "status": "started",
            "output": "line-2"
        ]

        let key1 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: base)
        let key2 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: changed)
        XCTAssertNotEqual(key1, key2)
    }

    func testRawDedupKeyRemainsStableForIdenticalPayload() {
        let payload: [String: String] = [
            "id": "cmd-1",
            "status": "completed",
            "output": "ok"
        ]
        let key1 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: payload)
        let key2 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: payload)
        XCTAssertEqual(key1, key2)
    }

    func testFileChangeParsesNestedPathCountersAndDiffPreview() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-1",
                "type": "file_change",
                "change_type": "create",
                "metadata": [
                    "target_path": "Tests/CoderIDETests/FontPreferencesTests.swift",
                    "stats": [
                        "insertions": 28,
                        "deletions_count": 0,
                    ],
                ],
                "patch": "@@ -0,0 +1 @@\n+import XCTest",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected file_change raw event")
            return
        }

        XCTAssertEqual(parsed.type, "file_change")
        XCTAssertEqual(parsed.payload["title"], "Created FontPreferencesTests.swift")
        XCTAssertEqual(parsed.payload["path"], "Tests/CoderIDETests/FontPreferencesTests.swift")
        XCTAssertEqual(parsed.payload["linesAdded"], "28")
        XCTAssertEqual(parsed.payload["linesRemoved"], "0")
        XCTAssertEqual(parsed.payload["change_type"], "create")
        XCTAssertEqual(parsed.payload["diffPreview"], "@@ -0,0 +1 @@\n+import XCTest")
    }

    func testFileChangeFallbackTitleWhenPathMissing() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-2",
                "type": "file_change",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected file_change raw event")
            return
        }

        XCTAssertEqual(parsed.payload["title"], "Edited file")
        XCTAssertEqual(parsed.payload["detail"], "")
    }

    func testFileChangeMinimalPayloadUsesGitHeadFallback() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-stream-fallback-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }

        try runGit(["init"], cwd: repo.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo.path)
        try runGit(["config", "user.name", "Codex Parser Test"], cwd: repo.path)

        let tracked = repo.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: tracked, atomically: true, encoding: .utf8)
        try runGit(["add", "Sample.swift"], cwd: repo.path)
        try runGit(["commit", "-m", "init"], cwd: repo.path)

        try "let value = 2\nlet extra = true\n".write(to: tracked, atomically: true, encoding: .utf8)

        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-minimal-1",
                "type": "file_change",
                "path": "Sample.swift",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json, workspacePath: repo.path) else {
            XCTFail("Expected file_change event with git fallback")
            return
        }

        XCTAssertEqual(parsed.type, "file_change")
        XCTAssertEqual(parsed.payload["diff_source"], "git_head_fallback")
        XCTAssertNotNil(parsed.payload["linesAdded"])
        XCTAssertNotNil(parsed.payload["linesRemoved"])
        XCTAssertTrue((parsed.payload["diffPreview"] ?? "").contains("let value = 2"))
    }

    func testFileChangeFallbackMarksUnavailableOutsideGitRepo() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "codex-stream-no-repo-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-minimal-2",
                "type": "file_change",
                "path": "Sample.swift",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json, workspacePath: workspace.path) else {
            XCTFail("Expected file_change event")
            return
        }

        XCTAssertEqual(parsed.payload["diff_source"], "unavailable")
    }

    func testFunctionCallToolEventMapsToInstantGrep() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "tool-1",
                "type": "function_call",
                "name": "grep",
                "arguments": [
                    "query": "trace activity",
                    "pathScope": "Sources/CoderIDE",
                ],
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected mapped tool raw event")
            return
        }

        XCTAssertEqual(parsed.type, "instant_grep")
        XCTAssertEqual(parsed.payload["query"], "trace activity")
        XCTAssertEqual(parsed.payload["pathScope"], "Sources/CoderIDE")
        XCTAssertEqual(parsed.payload["status"], "completed")
        XCTAssertEqual(parsed.payload["tool_call_id"], "tool-1")
    }

    func testFunctionCallMCPEventMapsToMCPToolCall() {
        let json: [String: Any] = [
            "type": "item.started",
            "item": [
                "id": "mcp-1",
                "type": "function_call",
                "name": "mcp_list_servers",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected mapped MCP event")
            return
        }

        XCTAssertEqual(parsed.type, "mcp_tool_call")
        XCTAssertEqual(parsed.payload["status"], "started")
        XCTAssertEqual(parsed.payload["tool_call_id"], "mcp-1")
        XCTAssertEqual(parsed.payload["is_mcp"], "true")
        XCTAssertTrue((parsed.payload["title"] ?? "").contains("MCP discovery"))
    }

    func testRawMCPToolCallNormalizesNamespacedToolIdentifier() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "mcp-2",
                "type": "mcp_tool_call",
                "name": "functions.mcp_list_servers",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected raw mcp_tool_call event")
            return
        }

        XCTAssertEqual(parsed.type, "mcp_tool_call")
        XCTAssertEqual(parsed.payload["tool"], "mcp_list_servers")
        XCTAssertEqual(parsed.payload["tool_raw"], "functions.mcp_list_servers")
        XCTAssertEqual(parsed.payload["is_mcp"], "true")
    }

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

    private func runParser(events input: [[String: Any]]) -> [StreamEvent] {
        var state = CodexCLIProvider.CodexStreamParserState()
        var out: [StreamEvent] = []
        for json in input {
            out.append(contentsOf: CodexCLIProvider.parseStreamJSONEvent(json, state: &state))
        }
        out.append(contentsOf: CodexCLIProvider.finalizeStreamJSONState(state: &state))
        return out
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return
        }
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(
            domain: "CodexCLIProviderStreamParsingTests",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(out) \(err)"
            ]
        )
    }
}
