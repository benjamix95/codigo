import Foundation
import XCTest

@testable import CoderEngine

final class GeminiCLIProviderStreamParsingTests: XCTestCase {
    func testReasoningUsesSwarmGroupIdWhenSwarmIdPresent() async throws {
        let script = try createMockGeminiScript(
            lines: ["{\"item\":{\"type\":\"reasoning\",\"swarm_id\":\"research-9\",\"text\":\"Selecting architecture\"}}"]
        )
        let workspace = script.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let provider = GeminiCLIProvider(geminiPath: script.path)
        let context = WorkspaceContext(workspacePath: FileManager.default.temporaryDirectory)

        let events = try await collectRawEvents(from: provider, context: context)
        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "research-9")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-research-9")
    }

    func testReasoningFallsBackToReasoningStreamWhenSwarmIdMissing() async throws {
        let script = try createMockGeminiScript(
            lines: ["{\"item\":{\"type\":\"reasoning\",\"text\":\"Fallback behavior\"}}"]
        )
        let workspace = script.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let provider = GeminiCLIProvider(geminiPath: script.path)
        let context = WorkspaceContext(workspacePath: FileManager.default.temporaryDirectory)

        let events = try await collectRawEvents(from: provider, context: context)
        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "reasoning-stream")
        XCTAssertNil(reasoningPayloads.first?["swarm_id"])
    }

    func testReasoningTrimmedSwarmIdGetsCanonicalGroupId() async throws {
        let script = try createMockGeminiScript(
            lines: ["{\"item\":{\"type\":\"reasoning\",\"swarm_id\":\"  swarm-analytics  \",\"text\":\"Whitespace normalization\"}}"]
        )
        let workspace = script.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let provider = GeminiCLIProvider(geminiPath: script.path)
        let context = WorkspaceContext(workspacePath: FileManager.default.temporaryDirectory)

        let events = try await collectRawEvents(from: provider, context: context)
        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "swarm-analytics")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-analytics")
    }

    private func collectRawEvents(
        from provider: GeminiCLIProvider,
        context: WorkspaceContext
    ) async throws -> [StreamEvent] {
        let stream = try await provider.send(prompt: "test", context: context)

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private func createMockGeminiScript(lines: [String]) throws -> URL {
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
        "gemini-stream-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

    let script = workspace.appendingPathComponent("mock-gemini")
    let payload = lines.map { "printf '%s\\n' '\($0)'" }.joined(separator: "\n")
    let scriptBody = "#!/bin/sh\n\(payload)\n"
    try scriptBody.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}
