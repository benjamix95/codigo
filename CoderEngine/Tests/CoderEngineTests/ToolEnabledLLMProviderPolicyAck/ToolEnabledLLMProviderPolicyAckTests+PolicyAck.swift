import Foundation
import XCTest
@testable import CoderEngine

// MARK: - Test helpers

extension ToolEnabledLLMProviderPolicyAckTests {

    final class SequencedEventProvider: LLMProvider, @unchecked Sendable {
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

    final class RoundSequencedEventProvider: LLMProvider, @unchecked Sendable {
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

    final class TextOnlyProvider: LLMProvider, @unchecked Sendable {
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

    final class DelayedTextOnlyProvider: LLMProvider, @unchecked Sendable {
        let id = "subagent-delayed-text"
        let displayName = "Subagent Delayed Text"
        private let delayNs: UInt64

        init(delayMs: UInt64) {
            self.delayNs = delayMs * 1_000_000
        }

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    continuation.yield(.started)
                    try? await Task.sleep(nanoseconds: delayNs)
                    continuation.yield(.textDelta("Delayed subagent output"))
                    continuation.yield(.completed)
                    continuation.finish()
                }
            }
        }
    }

    final class SilentSubagentProvider: LLMProvider, @unchecked Sendable {
        let id = "subagent-silent"
        let displayName = "Subagent Silent"
        private let delayNs: UInt64

        init(delayMs: UInt64) {
            self.delayNs = delayMs * 1_000_000
        }

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    continuation.yield(.started)
                    try? await Task.sleep(nanoseconds: delayNs)
                    continuation.yield(.completed)
                    continuation.finish()
                }
            }
        }
    }
    func testDoesNotInjectPolicyAckBeforeOperationalToolEvent() async throws {
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

        XCTAssertFalse(rawTypes.contains("policy_ack"))
        XCTAssertTrue(rawTypes.contains(where: { $0 == "read_batch_started" || $0 == "read_batch_completed" }))
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

    func testDoesNotInjectPolicyAckBeforeOperationalRawEvent() async throws {
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

        XCTAssertFalse(rawTypes.contains("policy_ack"))
        XCTAssertTrue(rawTypes.contains("command_execution"))
    }

}
