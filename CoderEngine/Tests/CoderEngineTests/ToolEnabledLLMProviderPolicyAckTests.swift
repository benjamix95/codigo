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
        let ackMarker = "[CODERIDE:policy_ack|hash=\(bundle.policyHash)]"
        let args = #"{"path":"\#(sourceFile.path)"}"#

        let base = SequencedEventProvider(events: [
            .textDelta(ackMarker),
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
}
