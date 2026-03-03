import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
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

    func testRawMCPSubagentToolCallDerivesSwarmMetadataFromToolName() {
        let json: [String: Any] = [
            "type": "item.started",
            "item": [
                "id": "mcp-sub-1",
                "type": "mcp_tool_call",
                "tool": "functions.mcp_call",
                "mcp_tool": "coderide_subagent_reviewer",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected raw subagent MCP event")
            return
        }

        XCTAssertEqual(parsed.type, "mcp_tool_call")
        XCTAssertEqual(parsed.payload["status"], "started")
        XCTAssertEqual(parsed.payload["swarm_id"], "reviewer")
        XCTAssertEqual(parsed.payload["group_id"], "swarm-reviewer")
    }

    func testRawMCPToolCallWithSwarmIdUsesCanonicalSwarmGroup() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "mcp-sub-2",
                "type": "mcp_tool_call",
                "tool": "functions.mcp_call",
                "mcp_tool": "coderide_list_dir",
                "swarm_id": "reviewer-42",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected raw MCP event with swarm_id")
            return
        }

        XCTAssertEqual(parsed.type, "mcp_tool_call")
        XCTAssertEqual(parsed.payload["swarm_id"], "reviewer-42")
        XCTAssertEqual(parsed.payload["group_id"], "swarm-reviewer-42")
    }

}
