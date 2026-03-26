import Foundation
import XCTest
@testable import CoderEngine

/// Copertura per `StreamEvent.error` su analisi / re-review multi-swarm (senza throw dal transport).
final class CodeReviewMultiSwarmProviderStreamErrorTests: XCTestCase {

    func testRunAnalysisPhaseThrowsAnalysisTransportFailedWhenProviderYieldsErrorEvent() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let context = WorkspaceContext(workspacePath: workspace, skipContextEnrichment: true)
        let provider = StubSequencedStreamProvider(events: [
            .textDelta("partial analysis "),
            .error("codex rate limited"),
        ])

        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    _ = try await CodeReviewMultiSwarmProvider.runAnalysisPhase(
                        cleanPrompt: "check",
                        scopeDescription: "scope",
                        ["f.swift"],
                        1,
                        context: context,
                        analysisProvider: provider,
                        continuation: continuation,
                        isCancelled: { false },
                        waitWhilePaused: { }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        do {
            for try await _ in stream {}
            XCTFail("Expected thrown ReviewPipelineError")
        } catch {
            guard let pipelineError = error as? CodeReviewMultiSwarmProvider.ReviewPipelineError else {
                XCTFail("Expected ReviewPipelineError, got \(error)")
                return
            }
            guard case .analysisTransportFailed(let message) = pipelineError else {
                XCTFail("Expected analysisTransportFailed, got \(pipelineError)")
                return
            }
            XCTAssertEqual(message, "codex rate limited")
        }
    }

    func testRunReReviewPhaseReturnsInconclusiveWhenProviderYieldsErrorEvent() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let context = WorkspaceContext(workspacePath: workspace, skipContextEnrichment: true)
        let provider = StubSequencedStreamProvider(events: [
            .textDelta("still issues"),
            .error("model stopped"),
        ])

        var outcome: CodeReviewMultiSwarmProvider.ReReviewOutcome?
        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                outcome = await CodeReviewMultiSwarmProvider.runReReviewPhase(
                    modifiedFiles: ["f.swift"],
                    round: 1,
                    context: context,
                    analysisProvider: provider,
                    maxWorkers: 1,
                    continuation: continuation,
                    isCancelled: { false },
                    waitWhilePaused: { }
                )
                continuation.finish()
            }
        }
        for try await _ in stream {}
        let final = try XCTUnwrap(outcome)
        if case .inconclusive(let reason) = final.findings {
            XCTAssertTrue(reason.contains("model stopped"), "unexpected reason: \(reason)")
        } else {
            XCTFail("Expected inconclusive findings, got \(final.findings)")
        }
    }

    func testSubagentProviderStreamErrorDescription() {
        let err = SubagentProviderStreamError(message: "hello")
        XCTAssertEqual(err.errorDescription, "hello")
    }
}

// MARK: - Stub

private struct StubSequencedStreamProvider: LLMProvider, Sendable {
    let id = "stub-sequenced-stream-error"
    let displayName = "Stub Sequenced Stream Error"

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
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
