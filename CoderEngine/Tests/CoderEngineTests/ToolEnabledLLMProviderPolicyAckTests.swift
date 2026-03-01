import Foundation
import XCTest
@testable import CoderEngine

final class ToolEnabledLLMProviderPolicyAckTests: XCTestCase {
    private final class SequencedEventProvider: LLMProvider, @unchecked Sendable {
        let id = "policy-ack-sequenced"
        let displayName = "Policy Ack Sequenced"

        private let events: [StreamEvent]

        init(events: [StreamEvent]) {
            self.events = events
        }

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.started)
                for event in events {
                    continuation.yield(event)
                }
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    private final class RoundSequencedEventProvider: LLMProvider, @unchecked Sendable {
        let id = "policy-ack-round-sequenced"
        let displayName = "Policy Ack Round Sequenced"

        private let rounds: [[StreamEvent]]
        private var cursor = 0
        private let lock = NSLock()

        init(rounds: [[StreamEvent]]) {
            self.rounds = rounds
        }

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            let roundEvents: [StreamEvent] = lock.withLock {
                guard !rounds.isEmpty else { return [] }
                let index = min(cursor, rounds.count - 1)
                cursor += 1
                return rounds[index]
            }
            return AsyncThrowingStream { continuation in
                continuation.yield(.started)
                for event in roundEvents {
                    continuation.yield(event)
                }
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    private final class TextOnlyProvider: LLMProvider, @unchecked Sendable {
        let id = "subagent-text-only"
        let displayName = "Subagent Text Only"

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.started)
                continuation.yield(.textDelta("Subagent completed task"))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    func testInjectsSyntheticPolicyAckBeforeOperationalToolEvent() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-ack-inject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(sourceFile.path)"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-1",
                "name": "read",
                "args": args,
                "is_partial": "false",
            ])
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Leggi Sample.swift",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var rawTypes: [String] = []
        for try await event in stream {
            if case .raw(let type, _) = event {
                rawTypes.append(type)
            }
        }

        let ackIndex = try XCTUnwrap(rawTypes.firstIndex(of: "policy_ack"))
        let operationalIndex = try XCTUnwrap(
            rawTypes.firstIndex(where: { $0 == "read_batch_started" || $0 == "read_batch_completed" })
        )
        XCTAssertLessThan(ackIndex, operationalIndex)
    }

    func testDoesNotDuplicatePolicyAckWhenModelAlreadyAcknowledged() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-ack-dedupe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let bundle = InstructionPolicyBundle.load(workspacePath: workspace.path)
        let args = #"{"path":"\#(sourceFile.path)"}"#

        let base = SequencedEventProvider(events: [
            // Model acknowledges policy via explicit policy_ack raw event
            .raw(type: "policy_ack", payload: ["hash": bundle.policyHash]),
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-2",
                "name": "read",
                "args": args,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Leggi Sample.swift",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var policyAckCount = 0
        for try await event in stream {
            if case .raw(let type, _) = event, type == "policy_ack" {
                policyAckCount += 1
            }
        }

        XCTAssertEqual(policyAckCount, 1)
    }

    func testToolCallSuggestedUsesDirectPayloadArgumentsWhenArgsJSONMissing() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-ack-direct-args-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-3",
                "name": "read",
                "path": sourceFile.path,
                "is_partial": "false",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Leggi Sample.swift",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var completedPayload: [String: String]?
        for try await event in stream {
            if case .raw(let type, let payload) = event,
               type == "read_batch_completed",
               payload["status"] == "completed" {
                completedPayload = payload
            }
        }

        let payload = try XCTUnwrap(completedPayload)
        XCTAssertEqual(payload["path"], sourceFile.path)
        XCTAssertTrue((payload["output"] ?? "").contains("let value = 1"))
    }

    func testInjectsSyntheticPolicyAckBeforeOperationalRawEvent() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("policy-ack-raw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = SequencedEventProvider(events: [
            .raw(type: "command_execution", payload: [
                "id": "cmd-raw-1",
                "status": "started",
                "title": "Running command",
                "detail": "ls -la",
            ]),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Mostra file",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var rawTypes: [String] = []
        for try await event in stream {
            if case .raw(let type, _) = event {
                rawTypes.append(type)
            }
        }

        let ackIndex = try XCTUnwrap(rawTypes.firstIndex(of: "policy_ack"))
        let commandIndex = try XCTUnwrap(rawTypes.firstIndex(of: "command_execution"))
        XCTAssertLessThan(ackIndex, commandIndex)
    }

    func testMCPEditRerouteMapsWriteToCoderideWrite() {
        let reroute = ToolEnabledLLMProvider.rerouteEditToolToMCP(
            toolName: "write",
            args: [
                "path": "Sources/CoderIDE/Trace.swift",
                "content": "let value = 1\n",
            ]
        )

        XCTAssertEqual(reroute?.mcpTool, "coderide_write")
        XCTAssertEqual(reroute?.args["path"], "Sources/CoderIDE/Trace.swift")
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
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var validationPayload: [String: String]?
        for try await event in stream {
            if case .raw(let type, let payload) = event,
               type == "tool_validation_error",
               payload["error_code"] == "mcp_edit_required" {
                validationPayload = payload
            }
        }

        XCTAssertEqual(validationPayload?["error_code"], "mcp_edit_required")
        XCTAssertEqual(validationPayload?["tool"], "write")
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
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
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
            if type == "agent", payload["detail"] == "started",
               (payload["swarm_id"] ?? "").hasPrefix("testWriter-") {
                sawStarted = true
            }
            if type == "tool_result",
               payload["status"] == "completed",
               payload["name"] == "subagent_testwriter",
               (payload["subagent_id"] ?? "").hasPrefix("testWriter-") {
                sawCompletedResult = true
            }
        }

        XCTAssertTrue(sawQueued)
        XCTAssertTrue(sawStarted)
        XCTAssertTrue(sawCompletedResult)
    }

    func testFirstRoundRejectsDirectOperationalToolWhenSubagentIsRequired() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-first-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(sourceFile.path)"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-direct-1",
                "name": "read",
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
            prompt: "Analizza il file",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var sawSubagentPolicyError = false
        var sawReadExecution = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_validation_error", payload["error_code"] == "subagent_first_required" {
                sawSubagentPolicyError = true
            }
            if type == "read_batch_started" || type == "read_batch_completed" {
                sawReadExecution = true
            }
        }

        XCTAssertTrue(sawSubagentPolicyError)
        XCTAssertFalse(sawReadExecution)
    }

    func testAutoInjectsReviewerAndTestWriterAfterCoderMutation() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-auto-review-\(UUID().uuidString)", isDirectory: true)
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
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 1,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Implementa e chiudi",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var sawReviewer = false
        var sawTestWriter = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_result",
               payload["name"] == "subagent_reviewer",
               payload["status"] == "completed" {
                sawReviewer = true
            }
            if type == "tool_result",
               payload["name"] == "subagent_testwriter",
               payload["status"] == "completed" {
                sawTestWriter = true
            }
        }

        XCTAssertTrue(sawReviewer, "Reviewer subagent should be auto-injected")
        XCTAssertTrue(sawTestWriter, "TestWriter subagent should be auto-injected")
    }

    func testAutoInjectsFinalReviewAgainAfterLaterMutation() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-auto-review-repeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let base = RoundSequencedEventProvider(rounds: [
            [
                .raw(type: "tool_call_suggested", payload: [
                    "id": "tc-coder-r1",
                    "name": "subagent_coder",
                    "args": #"{"task":"Round 1 change"}"#,
                    "is_partial": "false",
                ]),
            ],
            [
                .raw(type: "tool_call_suggested", payload: [
                    "id": "tc-coder-r2",
                    "name": "subagent_coder",
                    "args": #"{"task":"Round 2 change"}"#,
                    "is_partial": "false",
                ]),
            ],
            [],
        ])

        let provider = ToolEnabledLLMProvider(
            base: base,
            maxToolRounds: 4,
            subagentProviderFactory: { TextOnlyProvider() }
        )
        let stream = try await provider.send(
            prompt: "Implementa in due step",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var reviewerCompletions = 0
        var testWriterCompletions = 0
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            guard type == "tool_result", payload["status"] == "completed" else { continue }
            if payload["name"] == "subagent_reviewer" {
                reviewerCompletions += 1
            }
            if payload["name"] == "subagent_testwriter" {
                testWriterCompletions += 1
            }
        }

        XCTAssertGreaterThanOrEqual(
            reviewerCompletions,
            2,
            "Reviewer should run again after subsequent mutations"
        )
        XCTAssertGreaterThanOrEqual(
            testWriterCompletions,
            2,
            "TestWriter should run again after subsequent mutations"
        )
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
               payload["name"] == "subagent_testwriter",
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

        var sawReviewerAgentStarted = false
        var sawReviewerToolResult = false
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "agent",
               payload["status"] == "started",
               (payload["swarm_id"] ?? "").hasPrefix("reviewer-") {
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
               payload["name"] == "subagent_testwriter",
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
