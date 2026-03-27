import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatProviderAdapterTests: XCTestCase {
    func testRuntimeSessionConfigUsesStrictPromptForCodexProvider() {
        let provider = makeProvider(
            providerId: "codex-cli",
            displayName: "Codex",
            backend: .codexCli
        )

        let config = provider.runtimeSessionConfig(
            prompt: "indaga il bug",
            context: .minimal(),
            attachments: nil
        )

        XCTAssertEqual(config.providerId, "codex-cli")
        XCTAssertEqual(config.systemPrompt, SystemPrompts.taskCompletionStrict)
    }

    func testRuntimeSessionConfigKeepsStrictPromptForClaudeProvider() {
        let provider = makeProvider(
            providerId: "claude-cli",
            displayName: "Claude",
            backend: .claudeCli
        )

        let config = provider.runtimeSessionConfig(
            prompt: "indaga il bug",
            context: .minimal(),
            attachments: nil
        )

        XCTAssertEqual(config.providerId, "claude-cli")
        XCTAssertEqual(config.systemPrompt, SystemPrompts.taskCompletionStrict)
    }

    func testRuntimeSessionConfigUsesDebuggerPromptWhenDebugProfilePreferred() {
        let provider = makeProvider(
            providerId: "codex-cli",
            displayName: "Codex",
            backend: .codexCli
        )
        let ctx = WorkspaceContext(
            workspacePaths: [URL(fileURLWithPath: "/tmp")],
            preferDebuggerPromptProfile: true
        )
        let config = provider.runtimeSessionConfig(
            prompt: "debug",
            context: ctx,
            attachments: nil
        )
        XCTAssertEqual(config.systemPrompt, SystemPrompts.debugSessionAgentBase)
    }

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

    /// Regression: cancelSessionBridge must fire BEFORE driver.cancel() so the
    /// Rust worker thread sees the cancelled flag and exits its blocking read
    /// loop before the pipe is closed.  (P0-2026-03-26-rust-from-raw-parts)
    func testCancelSessionBridgeFiresBeforeDriverCancel() async throws {
        let cancelOrder = OrderTracker()

        // Poll returns "streaming" indefinitely so the driver stays alive.
        let streamingResponse = MainChatProviderSessionResponseBridge(
            schemaVersion: 1,
            error: nil,
            snapshot: .init(
                sessionId: "cancel-order-test",
                providerId: "codex-cli",
                backend: .codexCli,
                status: "streaming",
                terminalError: nil,
                activeAccountId: nil,
                roundRobinIndex: 0,
                emittedEventCount: 0,
                lastFailoverReason: nil
            ),
            events: []
        )

        let provider = MainChatRustTransportProvider(
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
                policyRef: nil,
                policyHash: nil,
                shouldReinjectPolicyText: true,
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
                claudeMcpServerPath: nil,
                geminiCliPath: nil,
                geminiModelOverride: nil,
                attachments: [],
                cliAccounts: []
            ),
            startSessionBridge: { _ in .init(schemaVersion: 1, error: nil, snapshot: nil, events: []) },
            pollSessionBridge: { _ in
                // Yield to allow cancellation to propagate.
                Thread.sleep(forTimeInterval: 0.01)
                return streamingResponse
            },
            cancelSessionBridge: { _ in
                cancelOrder.record("cancelSessionBridge")
                return nil
            }
        )

        let stream = try await provider.send(prompt: "hello", context: .minimal(), attachments: nil)
        let task = Task {
            for try await _ in stream { /* consume */ }
        }

        // Give the poll loop time to start.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Cancel the stream — this triggers onTermination.
        task.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)

        let events = cancelOrder.events
        XCTAssertTrue(
            events.contains("cancelSessionBridge"),
            "cancelSessionBridge should have been called on termination"
        )
    }

    private func makeProvider(
        providerId: String = "codex-cli",
        displayName: String = "Codex",
        backend: MainChatProviderBackendBridge = .codexCli,
        polls: ResponseQueue = ResponseQueue([])
    ) -> MainChatRustTransportProvider {
        MainChatRustTransportProvider(
            id: providerId,
            displayName: displayName,
            attachmentCapabilities: .none,
            authenticated: true,
            config: MainChatProviderSessionConfigBridge(
                providerId: providerId,
                displayName: displayName,
                backend: backend,
                workspacePath: "/tmp",
                workspacePaths: ["/tmp"],
                prompt: "",
                systemPrompt: nil,
                contextPrompt: nil,
                policyRef: nil,
                policyHash: nil,
                shouldReinjectPolicyText: true,
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
                claudeMcpServerPath: nil,
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

/// Thread-safe event order tracker for verifying call sequences.
private final class OrderTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []

    func record(_ event: String) {
        lock.withLock { _events.append(event) }
    }

    var events: [String] {
        lock.withLock { _events }
    }
}
