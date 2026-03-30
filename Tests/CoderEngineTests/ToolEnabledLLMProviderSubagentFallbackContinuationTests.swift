import Foundation
import XCTest
@testable import CoderEngine

final class ToolEnabledLLMProviderSubagentFallbackContinuationTests: XCTestCase {
    func testForkContextFallbackTextForcesSecondRoundAndLaunchesRealSubagent() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let parentBase = PromptCapturingFallbackProvider(rounds: [
            [
                .textDelta("I subagenti con fork del contesto non sono partiti per un limite del runtime; riprovo subito senza fork, passando il contesto esplicitamente."),
            ],
            [
                .raw(type: "tool_call_suggested", payload: [
                    "id": "sa-fallback-1",
                    "name": "subagent_explorer",
                    "task": "Inspect sidebar state management",
                ]),
            ],
        ])
        let childBase = ChildSubagentTextProvider()
        let provider = ToolEnabledLLMProvider(
            base: parentBase,
            maxToolRounds: 3,
            subagentProviderFactory: { childBase }
        )

        let stream = try await provider.send(
            prompt: "Analizza la sidebar e usa i subagent se disponibili.",
            context: WorkspaceContext(workspacePath: workspace, skipContextEnrichment: true),
            imageURLs: nil
        )

        var textDeltas: [String] = []
        var rawEvents: [(String, [String: String])] = []
        for try await event in stream {
            switch event {
            case .textDelta(let text):
                textDeltas.append(text)
            case .raw(let type, let payload):
                rawEvents.append((type, payload))
            default:
                break
            }
        }

        XCTAssertGreaterThanOrEqual(
            parentBase.prompts.count,
            2,
            "Il runtime deve continuare dopo il testo di fallback sul fork."
        )
        XCTAssertTrue(
            parentBase.prompts.dropFirst().contains(where: {
                $0.contains("Do NOT mention provider-native fork")
                    || $0.contains("Do NOT mention provider-native fork, fork_context")
            })
        )
        XCTAssertFalse(textDeltas.joined(separator: " ").lowercased().contains("fork del contesto"))
        XCTAssertTrue(rawEvents.contains { type, payload in
            type == "agent"
                && payload["tool_call_id"] == "sa-fallback-1"
        })
        XCTAssertTrue(rawEvents.contains { type, payload in
            type == "tool_result"
                && payload["id"] == "sa-fallback-1"
                && payload["status"] == "completed"
        })
    }
}

private final class PromptCapturingFallbackProvider: LLMProvider, @unchecked Sendable {
    let id = "fallback-parent-provider"
    let displayName = "Fallback Parent Provider"

    private let rounds: [[StreamEvent]]
    private let lock = NSLock()
    private var cursor = 0
    private var storedPrompts: [String] = []

    init(rounds: [[StreamEvent]]) {
        self.rounds = rounds
    }

    var prompts: [String] {
        lock.withLock { storedPrompts }
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context _: WorkspaceContext,
        imageURLs _: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let roundEvents: [StreamEvent] = lock.withLock {
            storedPrompts.append(prompt)
            guard cursor < rounds.count else { return [] }
            let index = cursor
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

private struct ChildSubagentTextProvider: LLMProvider, Sendable {
    let id = "fallback-child-provider"
    let displayName = "Fallback Child Provider"

    func isAuthenticated() -> Bool { true }

    func send(
        prompt _: String,
        context _: WorkspaceContext,
        imageURLs _: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.textDelta("Subagent explorer result"))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
