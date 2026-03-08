import Foundation
import XCTest
@testable import CoderEngine

extension ToolEnabledLLMProviderPolicyAckTests {
    func testReadSuggestionsRespectRoundBudgetAndEmitBudgetError() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tool-budget-read-exempt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let files = [
            workspace.appendingPathComponent("First.swift"),
            workspace.appendingPathComponent("Second.swift"),
            workspace.appendingPathComponent("Third.swift"),
            workspace.appendingPathComponent("Fourth.swift"),
        ]
        for (index, file) in files.enumerated() {
            try "let value\(index) = \(index)\n".write(to: file, atomically: true, encoding: .utf8)
        }

        let events: [StreamEvent] = files.enumerated().map { index, file in
            .raw(type: "tool_call_suggested", payload: [
                "id": "tc-read-budget-\(index)",
                "name": "read",
                "path": file.path,
                "is_partial": "false",
            ])
        }

        let provider = ToolEnabledLLMProvider(
            base: SequencedEventProvider(events: events),
            policy: ToolRuntimePolicy(maxToolCallsPerRound: 1),
            maxToolRounds: 1
        )
        let stream = try await provider.send(
            prompt: "Leggi più file",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var budgetExceededEvents = 0
        var completedReadEvents = 0
        for try await event in stream {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error", payload["error_code"] == "budget_exceeded" {
                budgetExceededEvents += 1
            }
            if type == "read_batch_completed", payload["status"] == "completed" {
                completedReadEvents += 1
            }
        }

        XCTAssertEqual(budgetExceededEvents, 1)
        XCTAssertEqual(completedReadEvents, 1)
    }
}
