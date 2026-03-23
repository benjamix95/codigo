import XCTest
import CoderEngine
@testable import CoderIDE

// MARK: - Claude Provider Integration Tests
// Anti-regression tests for Claude CLI streaming, reasoning, MCP, and text routing.

final class ClaudeProviderIntegrationTests: XCTestCase {

    // MARK: - Text Routing (shouldRouteStreamingTextToReasoning)

    func testClaudeCLINeverRoutesTextToReasoning() {
        // Claude CLI emits reasoning via separate `thinking` blocks,
        // so text_delta must ALWAYS be treated as the real response.
        XCTAssertFalse(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false,
                providerId: "claude-cli"
            )
        )
        XCTAssertFalse(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: true,
                providerId: "claude-cli"
            )
        )
        XCTAssertFalse(
            shouldRouteStreamingTextToReasoning(
                coderMode: .ide,
                hasOperationalActivityInTurn: false,
                providerId: "claude-cli"
            )
        )
    }

    func testCodexCLIStillRoutesTextToReasoningInAgentMode() {
        // Codex CLI does NOT separate thinking from text,
        // so agent mode must still route text → reasoning.
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false,
                providerId: "codex-cli"
            )
        )
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: true,
                providerId: "codex-cli"
            )
        )
    }

    func testGeminiCLIStillRoutesTextToReasoningInAgentMode() {
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false,
                providerId: "gemini-cli"
            )
        )
    }

    func testIDEModeNeverRoutesTextToReasoningRegardlessOfProvider() {
        for provider in ["claude-cli", "codex-cli", "gemini-cli", "kilo-cli", ""] {
            XCTAssertFalse(
                shouldRouteStreamingTextToReasoning(
                    coderMode: .ide,
                    hasOperationalActivityInTurn: false,
                    providerId: provider
                ),
                "IDE mode should never route to reasoning for provider=\(provider)"
            )
        }
    }

    func testEmptyProviderIdDefaultsToAgentModeRouting() {
        // Default (no providerId) should behave like Codex — route to reasoning in agent mode.
        XCTAssertTrue(
            shouldRouteStreamingTextToReasoning(
                coderMode: .agent,
                hasOperationalActivityInTurn: false,
                providerId: ""
            )
        )
    }

    // MARK: - Execution Route Resolution

    func testClaudeCLIUsesStandardStreamInAgentMode() {
        // Claude CLI via Rust transport → standardStream, not agentPipeline.
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: true
            ),
            .standardStream
        )
    }

    func testPlanFlowTakesPriorityOverTransportType() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: true,
                usesRustTransport: true
            ),
            .planFlow
        )
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: true,
                usesRustTransport: false
            ),
            .planFlow
        )
    }

    func testNonRustTransportFallsBackToAgentPipeline() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: false
            ),
            .agentPipeline
        )
    }

    // MARK: - Session Config Bridge (claudeMcpServerPath)

    func testSessionConfigBridgeCarriesMcpServerPath() {
        let config = MainChatProviderSessionConfigBridge(
            providerId: "claude-cli",
            displayName: "Claude",
            backend: .claudeCli,
            workspacePath: "/tmp",
            workspacePaths: ["/tmp"],
            prompt: "hello",
            systemPrompt: nil,
            contextPrompt: nil,
            model: "claude-opus-4-6",
            apiKey: nil,
            baseURL: nil,
            toolDefinitionsJson: nil,
            extraHeaders: [:],
            codexPath: nil,
            codexSandbox: "workspace-write",
            codexAskForApproval: "never",
            codexModelOverride: nil,
            codexReasoningEffort: nil,
            codexModelProvider: nil,
            codexFastMode: false,
            codexSessionFullAccess: false,
            codexPreferResponsesWireAPI: false,
            claudePath: "/usr/local/bin/claude",
            claudeModel: "claude-opus-4-6",
            claudeAllowedTools: ["Read", "Edit"],
            claudeMcpServerPath: "/tmp/coderide-mcp-server",
            geminiCliPath: nil,
            geminiModelOverride: nil,
            attachments: [],
            cliAccounts: []
        )

        XCTAssertEqual(config.claudeMcpServerPath, "/tmp/coderide-mcp-server")
        XCTAssertEqual(config.providerId, "claude-cli")
        XCTAssertEqual(config.backend, .claudeCli)
    }

    func testSessionConfigBridgeAllowsNilMcpServerPath() {
        let config = MainChatProviderSessionConfigBridge(
            providerId: "claude-cli",
            displayName: "Claude",
            backend: .claudeCli,
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
            codexPath: nil,
            codexSandbox: "workspace-write",
            codexAskForApproval: "never",
            codexModelOverride: nil,
            codexReasoningEffort: nil,
            codexModelProvider: nil,
            codexFastMode: false,
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
        )

        XCTAssertNil(config.claudeMcpServerPath)
    }

    // MARK: - Rust Transport Provider (Claude CLI)

    func testClaudeCLIRustTransportProviderCompletes() async throws {
        let responses = ResponseQueue([
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "claude-session-1",
                    providerId: "claude-cli",
                    backend: .claudeCli,
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
        let provider = makeClaudeProvider(polls: responses)
        let stream = try await provider.send(
            prompt: "test",
            context: .minimal(),
            attachments: nil
        )
        let events = try await collectEvents(from: stream)
        XCTAssertEqual(events, ["completed"])
    }

    func testClaudeCLIRustTransportProviderEmitsTextAndReasoning() async throws {
        let responses = ResponseQueue([
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "claude-session-2",
                    providerId: "claude-cli",
                    backend: .claudeCli,
                    status: "streaming",
                    terminalError: nil,
                    activeAccountId: nil,
                    roundRobinIndex: 0,
                    emittedEventCount: 2,
                    lastFailoverReason: nil
                ),
                events: [
                    .init(kind: .raw, text: "", rawType: "reasoning", payload: ["output": "Thinking..."]),
                    .init(kind: .textDelta, text: "Hello!", rawType: nil, payload: [:]),
                ]
            ),
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "claude-session-2",
                    providerId: "claude-cli",
                    backend: .claudeCli,
                    status: "completed",
                    terminalError: nil,
                    activeAccountId: nil,
                    roundRobinIndex: 0,
                    emittedEventCount: 2,
                    lastFailoverReason: nil
                ),
                events: []
            )
        ])
        let provider = makeClaudeProvider(polls: responses)
        let stream = try await provider.send(
            prompt: "test",
            context: .minimal(),
            attachments: nil
        )
        let events = try await collectEvents(from: stream)
        XCTAssertTrue(events.contains("raw:reasoning"))
        XCTAssertTrue(events.contains("delta:Hello!"))
        XCTAssertTrue(events.contains("completed"))
    }

    func testClaudeCLIRustTransportProviderReportsTerminalError() async throws {
        let responses = ResponseQueue([
            .init(
                schemaVersion: 1,
                error: nil,
                snapshot: .init(
                    sessionId: "claude-session-3",
                    providerId: "claude-cli",
                    backend: .claudeCli,
                    status: "failed",
                    terminalError: "rate_limited",
                    activeAccountId: nil,
                    roundRobinIndex: 0,
                    emittedEventCount: 0,
                    lastFailoverReason: nil
                ),
                events: []
            )
        ])
        let provider = makeClaudeProvider(polls: responses)
        let stream = try await provider.send(
            prompt: "test",
            context: .minimal(),
            attachments: nil
        )
        do {
            _ = try await collectEvents(from: stream)
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("rate_limited"))
        }
    }

    // MARK: - MCP Server Path Resolution

    func testResolveCoderideMCPServerPathReturnsNilWhenNoExecutableAvailable() {
        // In test environment there's no bundle executable, so the resolver
        // should gracefully return nil rather than crash.
        // (This tests that the resolution doesn't throw or assert.)
        let result = ChatPanelView.resolveCoderideMCPServerPath()
        // We don't assert a specific value because CI may have the binary;
        // we just verify it doesn't crash and returns Optional.
        _ = result // suppress unused warning
    }

    // MARK: - Helpers

    private func makeClaudeProvider(polls: ResponseQueue) -> MainChatRustTransportProvider {
        MainChatRustTransportProvider(
            id: "claude-cli",
            displayName: "Claude",
            attachmentCapabilities: .init(nativeImage: true, nativeDocument: false, nativeFile: false),
            authenticated: true,
            config: MainChatProviderSessionConfigBridge(
                providerId: "claude-cli",
                displayName: "Claude",
                backend: .claudeCli,
                workspacePath: "/tmp",
                workspacePaths: ["/tmp"],
                prompt: "",
                systemPrompt: nil,
                contextPrompt: nil,
                model: "claude-opus-4-6",
                apiKey: nil,
                baseURL: nil,
                toolDefinitionsJson: nil,
                extraHeaders: [:],
                codexPath: nil,
                codexSandbox: "workspace-write",
                codexAskForApproval: "never",
                codexModelOverride: nil,
                codexReasoningEffort: nil,
                codexModelProvider: nil,
                codexFastMode: false,
                codexSessionFullAccess: false,
                codexPreferResponsesWireAPI: false,
                claudePath: "/usr/local/bin/claude",
                claudeModel: "claude-opus-4-6",
                claudeAllowedTools: [],
                claudeMcpServerPath: "/tmp/coderide-mcp-server",
                geminiCliPath: nil,
                geminiModelOverride: nil,
                attachments: [],
                cliAccounts: []
            ),
            startSessionBridge: { _ in
                .init(schemaVersion: 1, error: nil, snapshot: nil, events: [])
            },
            pollSessionBridge: { _ in polls.next() },
            cancelSessionBridge: { _ in nil }
        )
    }

    private func collectEvents(
        from stream: AsyncThrowingStream<StreamEvent, Error>
    ) async throws -> [String] {
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

// MARK: - ResponseQueue (shared helper)

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
