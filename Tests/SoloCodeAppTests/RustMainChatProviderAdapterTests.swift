import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatProviderAdapterTests: XCTestCase {
    func testRustTransportProviderCompletesWhenPollReturnsCompletedSnapshot() async throws {
        let responses = ResponseQueue([
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "session-1",
                    providerId: "codex-cli",
                    backend: .codexCli,
                    status: "completed",
                    terminalError: nil,
                    activeAccountId: nil,
                    roundRobinIndex: 0,
                    emittedEventCount: 0,
                    lastFailoverReason: nil
                ),
                events: []
            )
        ])
        let provider = makeProvider(polls: responses)
        let stream = try await provider.send(prompt: "hello", context: .minimal(), attachments: nil)
        let events = try await collectEvents(from: stream)
        XCTAssertEqual(events, ["completed"])
    }

    func testRustTransportProviderThrowsWhenPollReturnsFailedSnapshot() async throws {
        let responses = ResponseQueue([
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "session-2",
                    providerId: "codex-cli",
                    backend: .codexCli,
                    status: "failed",
                    terminalError: "boom",
                    activeAccountId: nil,
                    roundRobinIndex: 0,
                    emittedEventCount: 0,
                    lastFailoverReason: nil
                ),
                events: []
            )
        ])
        let provider = makeProvider(polls: responses)
        let stream = try await provider.send(prompt: "hello", context: .minimal(), attachments: nil)
        do {
            _ = try await collectEvents(from: stream)
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }
    }

    private func makeProvider(polls: ResponseQueue) -> MainChatRustTransportProvider {
        MainChatRustTransportProvider(
            id: "codex-cli",
            displayName: "Codex",
            attachmentCapabilities: .none,
            authenticated: true,
            config: MainChatProviderSessionConfigBridge(
                providerId: "codex-cli",
                displayName: "Codex",
                backend: .codexCli,
                workspacePath: "/tmp",
                workspacePaths: ["/tmp"],
                prompt: "",
                systemPrompt: nil,
                contextPrompt: nil,
                model: nil,
                apiKey: nil,
                baseURL: nil,
                toolDefinitionsJson: nil,
                extraHeaders: [:],
                codexPath: "/usr/bin/codex",
                codexSandbox: "workspace-write",
                codexAskForApproval: "never",
                codexModelOverride: nil,
                codexReasoningEffort: nil,
                codexModelProvider: nil,
                codexFastMode: true,
                codexSessionFullAccess: false,
                codexPreferResponsesWireAPI: false,
                claudePath: nil,
                claudeModel: nil,
                claudeAllowedTools: [],
                geminiCliPath: nil,
                geminiModelOverride: nil,
                attachments: [],
                cliAccounts: []
            ),
            startSessionBridge: { _ in .init(schemaVersion: 1, error: nil, snapshot: nil, events: []) },
            pollSessionBridge: { _ in polls.next() },
            cancelSessionBridge: { _ in nil }
        )
    }

    private func collectEvents(from stream: AsyncThrowingStream<StreamEvent, Error>) async throws -> [String] {
        var collected: [String] = []
        for try await event in stream {
            switch event {
            case .started: collected.append("started")
            case .textDelta(let text): collected.append("delta:\(text)")
            case .textReplace(let text): collected.append("replace:\(text)")
            case .raw(let type, _): collected.append("raw:\(type)")
            case .completed: collected.append("completed")
            case .error(let message): collected.append("error:\(message)")
            }
        }
        return collected
    }
}

private final class ResponseQueue {
    private var responses: [MainChatProviderSessionResponseBridge]

    init(_ responses: [MainChatProviderSessionResponseBridge]) {
        self.responses = responses
    }

    func next() -> MainChatProviderSessionResponseBridge? {
        guard !responses.isEmpty else { return nil }
        return responses.removeFirst()
    }
}
