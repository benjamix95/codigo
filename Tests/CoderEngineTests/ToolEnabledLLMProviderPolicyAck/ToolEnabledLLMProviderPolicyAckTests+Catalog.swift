import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    func testExplicitUnknownToolDoesNotFallbackToReadHeuristic() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("explicit-unknown-no-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-unknown-1",
                "name": "totally_unknown_tool",
                "path": sourceFile.path, // would previously trigger read fallback
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Do something",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var sawReadExecution = false
        for try await event in stream {
            if case .raw(let type, _) = event,
               type == "read_batch_started" || type == "read_batch_completed" {
                sawReadExecution = true
            }
        }

        XCTAssertFalse(sawReadExecution)
    }

    func testDynamicCatalogRecognizesMCPBatchSuggestion() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("dynamic-catalog-mcp-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-mcp-batch-1",
                "name": "mcp_batch",
                "calls": "[]",
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Run mcp batch",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var sawMCPStart = false
        var sawMCPFailure = false
        var observed: [String] = []
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            observed.append("\(type):\(payload)")
            if type == "mcp_tool_call" {
                sawMCPStart = true
            }
            if type == "tool_execution_error",
               payload["tool"] == "mcp_batch",
               payload["status"] == "failed" {
                sawMCPFailure = true
            }
        }

        XCTAssertTrue(sawMCPStart, observed.joined(separator: " | "))
        XCTAssertTrue(sawMCPFailure, observed.joined(separator: " | "))
    }

    func testToolBudgetExceededIsEmittedOncePerRoundEvenWithManySuggestions() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-budget-dedupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-budget-1",
                "name": "bash",
                "command": "echo first",
                "is_partial": "false",
            ]),
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-budget-2",
                "name": "bash",
                "command": "echo second",
                "is_partial": "false",
            ]),
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-budget-3",
                "name": "bash",
                "command": "echo third",
                "is_partial": "false",
            ]),
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-budget-4",
                "name": "bash",
                "command": "echo fourth",
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            policy: ToolRuntimePolicy(maxToolCallsPerRound: 1),
            maxToolRounds: 1
        )
        let stream = try await provider.send(
            prompt: "Leggi più file",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var budgetExceededEvents = 0
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error", payload["error_code"] == "budget_exceeded" {
                budgetExceededEvents += 1
            }
        }

        XCTAssertEqual(budgetExceededEvents, 1)
    }

    func testMCPEditRerouteMapsWriteToCoderideWrite() {
        let reroute = ToolEnabledLLMProvider.rerouteEditToolToMCP(
            toolName: "write",
            args: [
                "path": "App/SoloCodeApp/Sources/Trace.swift",
                "content": "let value = 1\n",
            ]
        )

        XCTAssertEqual(reroute?.mcpTool, "coderide_write")
        XCTAssertEqual(reroute?.args["path"], "App/SoloCodeApp/Sources/Trace.swift")
        XCTAssertEqual(reroute?.args["content"], "let value = 1\n")
    }

    func testMCPEditRerouteReturnsNilForApplyPatch() {
        let reroute = ToolEnabledLLMProvider.rerouteEditToolToMCP(
            toolName: "apply_patch",
            args: [
                "patch": "*** Begin Patch\n*** End Patch\n",
            ]
        )
        XCTAssertNil(reroute)
    }

    func testEnforcedMCPEditEmitsValidationErrorWhenMCPDisabled() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-edit-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let target = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(target.path)","content":"let value = 2\n"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-mcp-enforce",
                "name": "write",
                "args": args,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            policy: ToolRuntimePolicy(enableMCP: false, enforceMCPEditOnly: true),
            maxToolRounds: 1
        )
        let stream = try await provider.send(
            prompt: "Aggiorna il file",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var validationPayload: [String: String]?
        var observed: [String] = []
        for try await event in stream {
            if case .raw(let type, let payload) = event {
               observed.append("\(type):\(payload)")
            }
            if case .raw(let type, let payload) = event,
               type == "tool_validation_error",
               payload["error_code"] == "mcp_edit_required" {
                validationPayload = payload
            }
        }

        XCTAssertEqual(validationPayload?["error_code"], "mcp_edit_required", observed.joined(separator: " | "))
        XCTAssertEqual(validationPayload?["tool"], "write", observed.joined(separator: " | "))
    }

    func testEnforcedMCPEditBlocksDeleteFileWhenMCPDisabled() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-edit-policy-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let target = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(target.path)"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-mcp-enforce-delete",
                "name": "delete_file",
                "args": args,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            policy: ToolRuntimePolicy(enableMCP: false, enforceMCPEditOnly: true),
            maxToolRounds: 1
        )
        let stream = try await provider.send(
            prompt: "Elimina il file",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var validationPayload: [String: String]?
        var observed: [String] = []
        for try await event in stream {
            if case .raw(let type, let payload) = event {
               observed.append("\(type):\(payload)")
            }
            if case .raw(let type, let payload) = event,
               type == "tool_validation_error",
               payload["error_code"] == "mcp_edit_required" {
                validationPayload = payload
            }
        }

        XCTAssertEqual(validationPayload?["error_code"], "mcp_edit_required", observed.joined(separator: " | "))
        XCTAssertEqual(validationPayload?["tool"], "delete_file", observed.joined(separator: " | "))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testSubagentTestWriterSuggestionIsAcceptedAndExecuted() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-testwriter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        // Ensure policy bundle exists so synthetic policy_ack path is exercised too.
        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let args = #"{"task":"Write tests for plan panel regressions"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-subagent-1",
                "name": "subagent_testWriter",
                "args": args,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Scrivi test mancanti",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        let identity = SubagentExecutionIdentityBuilder.make(
            role: .testWriter,
            task: "Write tests for plan panel regressions"
        )
        let normalizedToolName = ProviderToolEventMapper.normalizeToolIdentifier(
            SubagentRole.testWriter.toolName
        )
        var sawQueued = false
        var sawStarted = false
        var sawCompletedResult = false

        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "agent", payload["detail"] == "queued",
               (payload["swarm_id"] ?? "").hasPrefix("queued-") {
                sawQueued = true
            }
            if type == "agent", payload["status"] == "started",
               payload["swarm_id"] == identity.swarmId {
                sawStarted = true
            }
            if type == "tool_result",
               payload["status"] == "completed",
               [
                SubagentRole.testWriter.toolName,
                normalizedToolName,
               ].contains(payload["name"] ?? ""),
               payload["agent_name"] == identity.agentName {
                sawCompletedResult = true
            }
        }

        XCTAssertTrue(sawQueued)
        XCTAssertTrue(sawStarted)
        XCTAssertTrue(sawCompletedResult)
    }

}
