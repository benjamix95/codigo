import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    func testColdMCPRoundRejectsShellDiscoveryAndFollowUpPromptKeepsStructuredGuidance() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold-mcp-followup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceFile = workspace.appendingPathComponent("Sample.swift")
        try "let value = 1\n".write(to: sourceFile, atomically: true, encoding: .utf8)

        let registry = MCPNativeToolRegistry.shared
        registry.clear()
        defer { registry.clear() }

        let bashArgs = #"{\"command\":\"command rg --line-number value \#(workspace.path)\"}"#
        let base = PromptCapturingRoundSequencedProvider(rounds: [
            [
                .raw(type: "tool_call_suggested", payload: [
                    "id": "tc-cold-mcp-1",
                    "name": "bash",
                    "args": bashArgs,
                    "is_partial": "false",
                ]),
            ],
            [
                .textDelta("Uso i tool strutturati e preparo la risposta finale."),
            ],
        ])

        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 2)
        let stream = try await provider.send(
            prompt: "Trova dove viene usato value nel workspace e poi chiudi il task",
            context: nonPolicyContext(workspace: workspace),
            imageURLs: nil
        )

        var finalText = ""
        for try await event in stream {
            switch event {
            case .raw(let type, let payload):
                _ = type
                _ = payload
            case .textDelta(let delta):
                finalText += delta
            case .textReplace(let replacement):
                finalText = replacement
            default:
                break
            }
        }

        XCTAssertEqual(finalText, "Uso i tool strutturati e preparo la risposta finale.")

        let prompts = base.prompts
        XCTAssertGreaterThanOrEqual(prompts.count, 2)
        let secondPrompt = try XCTUnwrap(prompts.dropFirst().first)
        XCTAssertTrue(secondPrompt.contains("Tool results from previous round"))
        XCTAssertTrue(secondPrompt.contains("name=bash"))
        XCTAssertTrue(secondPrompt.contains("status=failed"))
        XCTAssertTrue(secondPrompt.contains("MCP registry warm-up"))
        XCTAssertTrue(secondPrompt.contains("coderide_semantic_search"))
        XCTAssertFalse(secondPrompt.contains("No MCP tools currently available"))
    }
}
