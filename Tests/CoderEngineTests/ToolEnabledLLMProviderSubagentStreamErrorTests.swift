import Foundation
import XCTest
@testable import CoderEngine

/// Verifica che `collectSubagentStreamOutput` propaghi `StreamEvent.error` come `SubagentProviderStreamError`
/// senza attendere il timeout lungo del task group (la task stream completa per prima).
final class ToolEnabledLLMProviderSubagentStreamErrorTests: XCTestCase {

    func testCollectSubagentStreamOutputThrowsWhenBaseYieldsStreamError() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        // `systemPromptOverride` forza `ToolEnabledLLMProvider.send` → `base.send` senza tool loop,
        // così gli eventi dello stub raggiungono `collectSubagentStreamOutput` invariati.
        let streamContext = WorkspaceContext(
            workspacePath: workspace,
            skipContextEnrichment: true,
            systemPromptOverride: "subagent-stream-error-test"
        )

        let stub = SubagentErrorStreamStub(events: [
            .started,
            .textDelta("partial "),
            .error("subagent stream failed"),
        ])
        let subagentProvider = ToolEnabledLLMProvider(base: stub, maxToolRounds: 1)
        let parent = ToolEnabledLLMProvider(base: stub, maxToolRounds: 1)

        let liveContext = SubagentLiveEventContext(
            role: .explorer,
            toolName: "subagent_explorer",
            toolCallId: "tc-collect-error",
            subagentId: "swarm-collect-error",
            agentName: "Explorer",
            taskSummary: "scan",
            backendProviderId: stub.id,
            backendDisplayName: stub.displayName,
            conversationId: nil
        )
        let liveState = SubagentLiveState(
            initialStage: .launchingBackend,
            initialDetail: "unit test"
        )
        let recorder = SubagentEventRecorder()
        do {
            _ = try await parent.collectSubagentStreamOutput(
                provider: subagentProvider,
                prompt: "explore",
                role: .explorer,
                context: streamContext,
                liveContext: liveContext,
                liveState: liveState,
                hasLiveCallback: false,
                eventRecorder: recorder,
                emitLiveOnly: { _ in }
            )
            XCTFail("Expected SubagentProviderStreamError")
        } catch {
            let streamErr = error as? SubagentProviderStreamError
            XCTAssertEqual(streamErr?.errorDescription, "subagent stream failed")
        }

        let recorded = await recorder.snapshot()
        let sawError = recorded.contains {
            if case .error(let message) = $0 { return message == "subagent stream failed" }
            return false
        }
        XCTAssertTrue(sawError, "Recorder should retain the error event before throw")
    }
}

// MARK: - Stub

private struct SubagentErrorStreamStub: LLMProvider, Sendable {
    let id = "subagent-error-stream-stub"
    let displayName = "Subagent Error Stream Stub"
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
