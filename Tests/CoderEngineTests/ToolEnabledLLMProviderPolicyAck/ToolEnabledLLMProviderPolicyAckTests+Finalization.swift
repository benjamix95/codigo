import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    func testTextReplaceCountsAsMeaningfulAssistantCompletion() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-final-textreplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(sourceFile.path)"}"#
        let base = SequencedEventProvider(events: [
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-replace-1",
                "name": "read",
                "args": args,
                "is_partial": "false",
            ]),
            .textReplace("Final answer emitted via replace with enough detail."),
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Leggi il file e chiudi il task",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var finalReplacement: String?
        var sawMissingFinalOutcome = false
        for try await event in stream {
            switch event {
            case .textReplace(let replacement):
                finalReplacement = replacement
            case .raw(let type, let payload):
                if type == "tool_execution_error",
                   payload["error_code"] == "missing_final_outcome" {
                    sawMissingFinalOutcome = true
                }
            default:
                break
            }
        }

        XCTAssertEqual(finalReplacement, "Final answer emitted via replace with enough detail.")
        XCTAssertFalse(sawMissingFinalOutcome)
    }

    func testForcedFinalizationAcceptsTextReplaceResponse() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-forced-textreplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let policyFile = workspace.appendingPathComponent("AGENTS.md")
        try "Policy test".write(to: policyFile, atomically: true, encoding: .utf8)

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let args = #"{"path":"\#(sourceFile.path)"}"#
        let base = RoundSequencedEventProvider(rounds: [
            [
                .raw(type: "tool_call_suggested", payload: [
                    "id": "tc-forced-1",
                    "name": "read",
                    "args": args,
                    "is_partial": "false",
                ]),
            ],
            [
                .textReplace("Forced final answer emitted via replace."),
            ],
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 1)
        let stream = try await provider.send(
            prompt: "Leggi e finalizza",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var sawForcedReplacement = false
        var sawMissingFinalOutcome = false
        for try await event in stream {
            switch event {
            case .textReplace(let replacement):
                if replacement == "Forced final answer emitted via replace." {
                    sawForcedReplacement = true
                }
            case .raw(let type, let payload):
                if type == "tool_execution_error",
                   payload["error_code"] == "missing_final_outcome" {
                    sawMissingFinalOutcome = true
                }
            default:
                break
            }
        }

        XCTAssertTrue(sawForcedReplacement)
        XCTAssertFalse(sawMissingFinalOutcome)
    }

    func testShellOutputIsRedactedFromFollowUpPrompt() {
        let provider = ToolEnabledLLMProvider(
            base: SequencedEventProvider(events: []),
            maxToolRounds: 1
        )

        let summary = provider.summarizeToolResultEvents(
            [
                .raw(type: "command_execution", payload: [
                    "status": "completed",
                    "detail": "Tests completed",
                    "output": "FAIL SampleTests.testExample()",
                ]),
            ],
            marker: CoderIDEMarker(kind: "tool_call", payload: [
                "id": "cmd-1",
                "name": "bash",
            ])
        )

        let prompt = provider.buildFollowUpPrompt(
            originalPrompt: "Run tests",
            transcript: "[assistant]\nRunning tests\n",
            toolResults: [summary ?? [:]]
        )

        XCTAssertNil(summary?["output"])
        XCTAssertFalse(prompt.contains("FAIL SampleTests.testExample()"))
    }

    func testSummarizeToolResultEventsPreservesResolvedMCPMetadata() {
        let provider = ToolEnabledLLMProvider(
            base: SequencedEventProvider(events: []),
            maxToolRounds: 1
        )

        let summary = provider.summarizeToolResultEvents(
            [
                .raw(type: "mcp_tool_call", payload: [
                    "status": "completed",
                    "detail": "Read complete",
                    "is_mcp": "true",
                    "mcp_tool": "coderide_read",
                    "mcp_server": "coderide",
                    "path": "/tmp/Sample.swift",
                ]),
            ],
            marker: CoderIDEMarker(kind: "tool_call", payload: [
                "id": "mcp-1",
                "name": "read",
            ])
        )

        XCTAssertEqual(summary?["name"], "read")
        XCTAssertEqual(summary?["is_mcp"], "true")
        XCTAssertEqual(summary?["mcp_tool"], "coderide_read")
        XCTAssertEqual(summary?["resolved_name"], "coderide_read")
        XCTAssertEqual(summary?["mcp_server"], "coderide")
    }

    func testFollowUpPromptIncludesResolvedMCPMetadata() {
        let provider = ToolEnabledLLMProvider(
            base: SequencedEventProvider(events: []),
            maxToolRounds: 1
        )

        let prompt = provider.buildFollowUpPrompt(
            originalPrompt: "Inspect the file",
            transcript: "[assistant]\nUsing MCP\n",
            toolResults: [[
                "id": "mcp-2",
                "name": "read",
                "status": "completed",
                "detail": "Read complete",
                "is_mcp": "true",
                "mcp_tool": "coderide_read",
                "mcp_server": "coderide",
            ]]
        )

        XCTAssertTrue(prompt.contains("resolved_mcp_tool: coderide_read @ coderide"))
        XCTAssertTrue(prompt.contains("name=read"))
    }
}
