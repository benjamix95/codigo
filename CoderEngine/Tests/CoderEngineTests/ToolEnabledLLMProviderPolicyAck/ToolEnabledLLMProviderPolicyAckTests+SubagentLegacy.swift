import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    private var normalizedTestWriterToolName: String {
        ProviderToolEventMapper.normalizeToolIdentifier(SubagentRole.testWriter.toolName)
    }

    func testSubagentBatchDonePayloadIncludesCompletedRoles() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-batch-roles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-reviewer-1",
                "name": "subagent_reviewer",
                "args": #"{"task":"Review all changes"}"#,
                "is_partial": "false",
            ]),
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-testwriter-1",
                "name": "subagent_testWriter",
                "args": #"{"task":"Run regression tests"}"#,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Esegui review e test finali",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var batchRoles = Set<String>()
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            guard type == "subagent_batch_done" else { continue }
            let parsedRoles = (payload["roles"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            batchRoles.formUnion(parsedRoles)
        }

        XCTAssertTrue(batchRoles.contains("reviewer"))
        XCTAssertTrue(batchRoles.contains("testwriter"))
    }

    func testSubagentBatchDonePayloadExcludesInvalidSubagentRoles() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-batch-invalid-roles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-reviewer-invalid-roles",
                "name": "subagent_reviewer",
                "args": #"{}"#,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Prova reviewer senza task",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var observedBatchPayloads: [[String: String]] = []
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            guard type == "subagent_batch_done" else { continue }
            observedBatchPayloads.append(payload)
        }

        let firstBatchPayload = try XCTUnwrap(observedBatchPayloads.first)
        let roles = Set(
            (firstBatchPayload["roles"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        XCTAssertFalse(roles.contains("reviewer"))
    }

    func testFailedReviewerSuggestionDoesNotSatisfyMandatoryFinalReview() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-reviewer-failed-suggestion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-coder-1",
                "name": "subagent_coder",
                "args": #"{"task":"Implement fix"}"#,
                "is_partial": "false",
            ]),
            // Invalid reviewer call: missing task should fail validation and must
            // NOT count as completed review coverage.
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-reviewer-invalid",
                "name": "subagent_reviewer",
                "args": #"{}"#,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 2,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Implementa e verifica",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var sawMissingTaskValidation = false
        var reviewerCompleted = false
        var testWriterCompleted = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_validation_error",
               payload["error_code"] == "missing_argument",
               payload["name"] == "subagent_reviewer" {
                sawMissingTaskValidation = true
            }
            if type == "tool_result",
               payload["name"] == "subagent_reviewer",
               payload["status"] == "completed" {
                reviewerCompleted = true
            }
            if type == "tool_result",
               [
                SubagentRole.testWriter.toolName,
                normalizedTestWriterToolName,
               ].contains(payload["name"] ?? ""),
               payload["status"] == "completed" {
                testWriterCompleted = true
            }
        }

        XCTAssertTrue(sawMissingTaskValidation, "Initial invalid reviewer call should fail validation")
        XCTAssertTrue(reviewerCompleted, "Reviewer should be auto-injected after invalid suggestion")
        XCTAssertTrue(testWriterCompleted, "TestWriter should be auto-injected for mandatory final review")
    }

    func testLegacyInvokeSwarmToolIsAdaptedToSubagentExecution() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-invoke-swarm-direct-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-legacy-invoke-direct",
                "name": "invoke_swarm",
                "args": #"{"task":"Review all changes","role":"reviewer"}"#,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Fai review finale",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        let reviewerIdentity = SubagentExecutionIdentityBuilder.make(
            role: .reviewer,
            task: "Review all changes"
        )
        var sawReviewerAgentStarted = false
        var sawReviewerToolResult = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "agent",
               payload["status"] == "started",
               payload["swarm_id"] == reviewerIdentity.swarmId {
                sawReviewerAgentStarted = true
            }
            if type == "tool_result",
               payload["name"] == "subagent_reviewer",
               payload["status"] == "completed" {
                sawReviewerToolResult = true
            }
        }

        XCTAssertTrue(sawReviewerAgentStarted)
        XCTAssertTrue(sawReviewerToolResult)
    }

    func testLegacyInvokeSwarmViaMCPCallIsAdaptedToSubagentExecution() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-invoke-swarm-mcp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-legacy-invoke-mcp",
                "name": "mcp_call",
                "args": #"{"server":"coderide","tool":"coderide_invoke_swarm","task":"write tests for changes","role":"testwriter"}"#,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Esegui swarm legacy",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var sawTestWriterToolResult = false
        var sawLegacyMCPToolCall = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_result",
               payload["name"] == normalizedTestWriterToolName,
               payload["status"] == "completed" {
                sawTestWriterToolResult = true
            }
            if type == "mcp_tool_call",
               payload["mcp_tool"] == "coderide_invoke_swarm" || payload["tool"] == "invoke_swarm" {
                sawLegacyMCPToolCall = true
            }
        }

        XCTAssertTrue(sawTestWriterToolResult)
        XCTAssertFalse(sawLegacyMCPToolCall, "Legacy invoke_swarm should be adapted before MCP runtime execution")
    }
}
