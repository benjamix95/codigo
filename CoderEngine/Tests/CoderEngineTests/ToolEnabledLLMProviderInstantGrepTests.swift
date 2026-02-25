import Foundation
import XCTest
@testable import CoderEngine

final class ToolEnabledLLMProviderInstantGrepTests: XCTestCase {
    private final class SequencedProvider: LLMProvider, @unchecked Sendable {
        let id = "sequenced-provider"
        let displayName = "Sequenced Provider"

        private let lock = NSLock()
        private let deltas: [String]
        private var callIndex = 0

        init(deltas: [String]) {
            self.deltas = deltas
        }

        func isAuthenticated() -> Bool { true }

        func send(
            prompt _: String,
            context _: WorkspaceContext,
            imageURLs _: [URL]?
        ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            let delta: String = {
                lock.lock()
                defer { lock.unlock() }
                let index = min(callIndex, max(0, deltas.count - 1))
                callIndex += 1
                return deltas[index]
            }()

            return AsyncThrowingStream { continuation in
                continuation.yield(.started)
                if !delta.isEmpty {
                    continuation.yield(.textDelta(delta))
                }
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    func testInstantGrepEmitsRichPayloadFromRuntimeSearch() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("instant-grep-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("Sample.swift")
        try "let hello = 1\nfunc greet() { print(hello) }\n".write(to: file, atomically: true, encoding: .utf8)

        let marker = "[CODERIDE:instant_grep|id=ig1|query=hello|pathScope=.]"
        let base = SequencedProvider(deltas: [marker, "Final answer"])
        let provider = ToolEnabledLLMProvider(base: base, maxToolRounds: 4)

        let stream = try await provider.send(
            prompt: "Find hello usage",
            context: WorkspaceContext(workspacePath: workspace),
            imageURLs: nil
        )

        var instantPayload: [String: String]?
        for try await event in stream {
            if case .raw(let type, let payload) = event, type == "instant_grep" {
                instantPayload = payload
            }
        }

        let payload = try XCTUnwrap(instantPayload)
        XCTAssertEqual(payload["query"], "hello")
        XCTAssertEqual(payload["pathScope"], ".")
        XCTAssertFalse((payload["duration_ms"] ?? "").isEmpty)

        let matchesCount = Int(payload["matchesCount"] ?? "") ?? 0
        XCTAssertGreaterThan(matchesCount, 0)

        let preview = payload["previewLines"] ?? ""
        XCTAssertTrue(preview.contains("hello"), "Expected preview lines to contain query match")
    }
}
