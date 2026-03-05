import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
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
               payload["name"] == SubagentRole.testWriter.toolName,
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
            if payload["name"] == SubagentRole.testWriter.toolName {
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

}
