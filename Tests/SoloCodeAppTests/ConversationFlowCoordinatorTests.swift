import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class ConversationFlowCoordinatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testRunStreamCallsOnTextIncrementallyForEachDelta() async throws {
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: ["main": "Ciao"],
                    uiEvents: [.init(kind: .textDelta, text: "Ciao", rawType: nil, payload: [:])]
                ),
                .init(
                    textByStreamId: ["main": "Ciao mondo"],
                    uiEvents: [
                        .init(kind: .textDelta, text: " mondo", rawType: nil, payload: [:]),
                        .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                    ],
                    status: "completed",
                    isTerminal: true
                ),
            ]
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var snapshots: [String] = []
        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { snapshots.append($0) },
            onRaw: { _, _, _ in },
            onError: { _ in }
        )

        XCTAssertEqual(snapshots, ["Ciao", "Ciao mondo"])
        XCTAssertEqual(result, "Ciao mondo")
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testRunStreamHandlesRawHeavyBurstWithoutBlockingTextPropagation() async throws {
        let rawEvents = (0..<250).map { idx in
            MainChatRuntimeUIEventBridge(kind: .raw, text: "", rawType: "command_execution", payload: [
                "id": "cmd-\(idx)",
                "status": "in_progress"
            ])
        }
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: ["main": "Final output"],
                    uiEvents: rawEvents + [
                        .init(kind: .textDelta, text: "Final output", rawType: nil, payload: [:]),
                        .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                    ],
                    status: "completed",
                    isTerminal: true
                )
            ]
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var snapshots: [String] = []
        var rawCount = 0
        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { snapshots.append($0) },
            onRaw: { _, _, _ in rawCount += 1 },
            onError: { _ in }
        )

        XCTAssertEqual(rawCount, 250)
        XCTAssertEqual(snapshots.last, "Final output")
        XCTAssertEqual(result, "Final output")
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testRunStreamBuffersOperationalRawEventsUntilFirstNarrativeEvent() async throws {
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: ["main": "Risposta iniziale"],
                    uiEvents: [
                        .init(kind: .raw, text: "", rawType: "mcp_tool_call", payload: ["mcp_tool": "coderide_read", "status": "in_progress"]),
                        .init(kind: .raw, text: "", rawType: "reasoning", payload: ["output": "Sto pensando"]),
                        .init(kind: .textDelta, text: "Risposta iniziale", rawType: nil, payload: [:]),
                        .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                    ],
                    status: "completed",
                    isTerminal: true
                )
            ],
            providerId: "claude-cli"
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var callbacks: [String] = []
        _ = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { _ in callbacks.append("text") },
            onRaw: { type, _, _ in callbacks.append("raw:\(type)") },
            onError: { _ in }
        )

        // The reasoning event is the first narrative marker, which triggers
        // flushing the buffered mcp_tool_call. Then textDelta arrives as text.
        XCTAssertEqual(
            callbacks,
            ["raw:reasoning", "raw:mcp_tool_call", "text"]
        )
    }

    func testRunStreamIgnoresCodexReasoningAsNarrativeAndWaitsForRealAnswerText() async throws {
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: ["main": "Risposta finale"],
                    uiEvents: [
                        .init(kind: .raw, text: "", rawType: "mcp_tool_call", payload: ["mcp_tool": "coderide_read", "status": "in_progress"]),
                        .init(kind: .raw, text: "", rawType: "reasoning", payload: ["output": "Sto pensando"]),
                        .init(kind: .textDelta, text: "Risposta finale", rawType: nil, payload: [:]),
                        .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                    ],
                    status: "completed",
                    isTerminal: true
                )
            ]
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var callbacks: [String] = []
        _ = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { _ in callbacks.append("text") },
            onRaw: { type, _, _ in callbacks.append("raw:\(type)") },
            onError: { _ in }
        )

        XCTAssertEqual(callbacks, ["text", "raw:mcp_tool_call"])
    }

    func testRunStreamCanExecuteOffMainActorWhileDispatchingCallbacksOnMain() async throws {
        let result = try await Task.detached { () throws -> (String, ConversationFlowCoordinator.State) in
            let provider = self.makeRustTransportProvider(
                polls: [
                    .init(
                        textByStreamId: ["main": "ok"],
                        uiEvents: [
                            .init(kind: .raw, text: "", rawType: "command_execution", payload: ["id": "cmd-1", "status": "started"]),
                            .init(kind: .textDelta, text: "ok", rawType: nil, payload: [:]),
                            .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                        ],
                        status: "completed",
                        isTerminal: true
                    )
                ]
            )
            let coordinator = ConversationFlowCoordinator()
            let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

            let streamResult = try await coordinator.runStream(
                provider: provider,
                prompt: "test",
                context: ctx,
                attachments: nil,
                onText: { _ in
                    XCTAssertTrue(Thread.isMainThread)
                },
                onRaw: { _, _, _ in
                    XCTAssertTrue(Thread.isMainThread)
                },
                onError: { _ in
                    XCTFail("onError not expected")
                }
            )
            let state = await MainActor.run { coordinator.state }
            return (streamResult, state)
        }.value

        XCTAssertEqual(result.0, "ok")
        XCTAssertEqual(result.1, .completed)
    }

    func testRunStreamFailsWhenProviderEmitsErrorEvent() async {
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: ["main": "partial"],
                    uiEvents: [
                        .init(kind: .textDelta, text: "partial", rawType: nil, payload: [:]),
                        .init(kind: .error, text: "boom", rawType: nil, payload: [:]),
                    ],
                    status: "failed",
                    terminalError: "boom",
                    isTerminal: true
                )
            ]
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var snapshots: [String] = []
        do {
            _ = try await coordinator.runStream(
                provider: provider,
                prompt: "test",
                context: ctx,
                attachments: nil,
                onText: { _ in },
                onRaw: { _, _, _ in },
                onError: { snapshots.append($0) }
            )
            XCTFail("Expected provider error to fail the stream")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("boom"))
        }

        XCTAssertEqual(coordinator.state, .error)
        XCTAssertEqual(snapshots.last, "partial\n\n[Error: boom]")
    }

    func testRunStreamReusesPendingReadAcrossInitialTimeoutRetries() async throws {
        let provider = makeRustTransportProvider(
            polls: [
                .init(
                    textByStreamId: [:],
                    uiEvents: [],
                    shouldRetryPoll: true,
                    didTimeout: true
                ),
                .init(
                    textByStreamId: ["main": "late"],
                    uiEvents: [
                        .init(kind: .textDelta, text: "late", rawType: nil, payload: [:]),
                        .init(kind: .completed, text: "", rawType: nil, payload: [:]),
                    ],
                    status: "completed",
                    isTerminal: true
                )
            ]
        )
        let coordinator = ConversationFlowCoordinator(
            initialEventTimeoutOverride: 1,
            initialRetryOverride: 2
        )
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var snapshots: [String] = []
        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { snapshots.append($0) },
            onRaw: { _, _, _ in },
            onError: { _ in }
        )

        XCTAssertEqual(snapshots, ["late"])
        XCTAssertEqual(result, "late")
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testRunStreamFailsClosedWhenRustRuntimeIsForcedOff() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let provider = makeRustTransportProvider(polls: [])
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        do {
            _ = try await coordinator.runStream(
                provider: provider,
                prompt: "test",
                context: ctx,
                attachments: nil,
                onText: { _ in },
                onRaw: { _, _, _ in },
                onError: { _ in }
            )
            XCTFail("Expected Rust-only direct runtime to fail closed when Rust is forced off")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Rust main chat direct stream runtime unavailable"))
        }

        XCTAssertEqual(coordinator.state, .error)
    }

    func testRunStreamReducesRustPolledProviderEventsWithoutSwiftEventMapping() async throws {
        let polls = RuntimePollQueue()
        polls.enqueue { request in
            var snapshot = request.snapshot
            snapshot.turnState = MainChatBridgeState(
                conversationId: snapshot.turnState.conversationId,
                assistantMessageId: snapshot.turnState.assistantMessageId,
                turnId: snapshot.turnState.turnId,
                providerId: snapshot.turnState.providerId,
                sequence: snapshot.turnState.sequence,
                isStreaming: snapshot.turnState.isStreaming,
                startedAt: snapshot.turnState.startedAt,
                completedAt: snapshot.turnState.completedAt,
                updatedAt: snapshot.turnState.updatedAt,
                status: snapshot.turnState.status,
                orderedTextStreamIds: ["main"],
                textByStreamId: ["main": "ciao"],
                reasoningByGroupId: snapshot.turnState.reasoningByGroupId,
                artifacts: snapshot.turnState.artifacts
            )
            snapshot.directStream?.hasReceivedAnyEvent = true
            snapshot.directStream?.emittedFirstText = true
            return MainChatRuntimeProviderPollBridgeResponse(
                schemaVersion: 1,
                error: nil,
                runtimeSnapshot: snapshot,
                signals: [],
                uiEvents: [
                    MainChatRuntimeUIEventBridge(
                        kind: .textDelta,
                        text: "ciao",
                        rawType: nil,
                        payload: [:]
                    ),
                    MainChatRuntimeUIEventBridge(
                        kind: .raw,
                        text: "",
                        rawType: "command_execution",
                        payload: ["id": "cmd-1", "status": "running"]
                    ),
                ],
                isTerminal: false,
                didTimeout: false
            )
        }
        polls.enqueue { request in
            var snapshot = request.snapshot
            snapshot.turnState = MainChatBridgeState(
                conversationId: snapshot.turnState.conversationId,
                assistantMessageId: snapshot.turnState.assistantMessageId,
                turnId: snapshot.turnState.turnId,
                providerId: snapshot.turnState.providerId,
                sequence: snapshot.turnState.sequence,
                isStreaming: snapshot.turnState.isStreaming,
                startedAt: snapshot.turnState.startedAt,
                completedAt: snapshot.turnState.completedAt,
                updatedAt: snapshot.turnState.updatedAt,
                status: "completed",
                orderedTextStreamIds: ["main"],
                textByStreamId: ["main": "ciao mondo"],
                reasoningByGroupId: snapshot.turnState.reasoningByGroupId,
                artifacts: snapshot.turnState.artifacts
            )
            snapshot.directStream?.hasReceivedAnyEvent = true
            snapshot.directStream?.emittedFirstText = true
            return MainChatRuntimeProviderPollBridgeResponse(
                schemaVersion: 1,
                error: nil,
                runtimeSnapshot: snapshot,
                signals: [],
                uiEvents: [
                    MainChatRuntimeUIEventBridge(
                        kind: .textDelta,
                        text: " mondo",
                        rawType: nil,
                        payload: [:]
                    ),
                    MainChatRuntimeUIEventBridge(
                        kind: .completed,
                        text: "",
                        rawType: nil,
                        payload: [:]
                    ),
                ],
                isTerminal: true,
                didTimeout: false
            )
        }

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
            pollSessionBridge: { _ in nil },
            cancelSessionBridge: { _ in nil },
            runtimePollBridge: { request in polls.next(for: request) }
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        var snapshots: [String] = []
        var rawEvents: [(String, [String: String])] = []
        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { snapshots.append($0) },
            onRaw: { type, payload, _ in rawEvents.append((type, payload)) },
            onError: { _ in }
        )

        XCTAssertEqual(snapshots, ["ciao", "ciao mondo"])
        XCTAssertEqual(rawEvents.count, 1)
        XCTAssertEqual(rawEvents.first?.0, "command_execution")
        XCTAssertEqual(rawEvents.first?.1["id"], "cmd-1")
        XCTAssertEqual(result, "ciao mondo")
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testRunStreamFailsWhenRustPolledProviderReturnsTimeoutErrorEvent() async {
        let polls = RuntimePollQueue()
        polls.enqueue { request in
            var snapshot = request.snapshot
            snapshot.output = MainChatRuntimeOutputBridge(
                chatContentOverride: nil,
                shouldHidePlanMarkdown: false,
                shouldOpenPlanPanel: false,
                shouldFinalizeStream: true,
                shouldRetryPoll: false,
                followUpPrompt: nil,
                generatedPrompt: nil,
                terminalError: "Rust timeout"
            )
            return MainChatRuntimeProviderPollBridgeResponse(
                schemaVersion: 1,
                error: nil,
                runtimeSnapshot: snapshot,
                signals: [],
                uiEvents: [
                    MainChatRuntimeUIEventBridge(
                        kind: .error,
                        text: "Rust timeout",
                        rawType: nil,
                        payload: [:]
                    )
                ],
                isTerminal: true,
                didTimeout: true
            )
        }

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
            pollSessionBridge: { _ in nil },
            cancelSessionBridge: { _ in nil },
            runtimePollBridge: { request in polls.next(for: request) }
        )
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        do {
            _ = try await coordinator.runStream(
                provider: provider,
                prompt: "test",
                context: ctx,
                attachments: nil,
                onText: { _ in },
                onRaw: { _, _, _ in },
                onError: { _ in }
            )
            XCTFail("Expected timeout-driven provider failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Rust timeout"))
        }

        XCTAssertEqual(coordinator.state, .error)
    }

    func testRunStreamUsesRustPollSignalsInsteadOfSnapshotDiffForLifecycleCallbacks() async throws {
        let polls = RuntimePollQueue()
        polls.enqueue { request in
            var snapshot = request.snapshot
            snapshot.turnState = MainChatBridgeState(
                conversationId: snapshot.turnState.conversationId,
                assistantMessageId: snapshot.turnState.assistantMessageId,
                turnId: snapshot.turnState.turnId,
                providerId: snapshot.turnState.providerId,
                sequence: snapshot.turnState.sequence,
                isStreaming: true,
                startedAt: snapshot.turnState.startedAt,
                completedAt: snapshot.turnState.completedAt,
                updatedAt: snapshot.turnState.updatedAt,
                status: "streaming",
                orderedTextStreamIds: ["main"],
                textByStreamId: ["main": "ciao"],
                reasoningByGroupId: snapshot.turnState.reasoningByGroupId,
                artifacts: snapshot.turnState.artifacts
            )
            snapshot.directStream?.hasReceivedAnyEvent = false
            snapshot.directStream?.emittedFirstText = false
            return MainChatRuntimeProviderPollBridgeResponse(
                schemaVersion: 1,
                error: nil,
                runtimeSnapshot: snapshot,
                signals: [.firstEvent, .firstTextDelta],
                uiEvents: [
                    MainChatRuntimeUIEventBridge(
                        kind: .textDelta,
                        text: "ciao",
                        rawType: nil,
                        payload: [:]
                    )
                ],
                isTerminal: false,
                didTimeout: false
            )
        }
        polls.enqueue { request in
            var snapshot = request.snapshot
            snapshot.turnState = MainChatBridgeState(
                conversationId: snapshot.turnState.conversationId,
                assistantMessageId: snapshot.turnState.assistantMessageId,
                turnId: snapshot.turnState.turnId,
                providerId: snapshot.turnState.providerId,
                sequence: snapshot.turnState.sequence,
                isStreaming: false,
                startedAt: snapshot.turnState.startedAt,
                completedAt: Date(),
                updatedAt: snapshot.turnState.updatedAt,
                status: "completed",
                orderedTextStreamIds: ["main"],
                textByStreamId: ["main": "ciao"],
                reasoningByGroupId: snapshot.turnState.reasoningByGroupId,
                artifacts: snapshot.turnState.artifacts
            )
            return MainChatRuntimeProviderPollBridgeResponse(
                schemaVersion: 1,
                error: nil,
                runtimeSnapshot: snapshot,
                signals: [.streamCompleted],
                uiEvents: [
                    MainChatRuntimeUIEventBridge(
                        kind: .completed,
                        text: "",
                        rawType: nil,
                        payload: [:]
                    )
                ],
                isTerminal: true,
                didTimeout: false
            )
        }

        let provider = makeRustTransportProvider(polls: [], queue: polls)
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        var signals: [ConversationFlowCoordinator.StreamSignal] = []

        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { _ in },
            onRaw: { _, _, _ in },
            onError: { _ in },
            onSignal: { signals.append($0) }
        )

        XCTAssertEqual(result, "ciao")
        XCTAssertEqual(
            signals.map {
                switch $0 {
                case .streamStarted: return "streamStarted"
                case .firstEvent: return "firstEvent"
                case .firstTextDelta: return "firstTextDelta"
                case .streamCompleted: return "streamCompleted"
                }
            },
            ["streamStarted", "firstEvent", "firstTextDelta", "streamCompleted"]
        )
    }

    nonisolated private func makeRustTransportProvider(
        polls: [RuntimePollResult],
        queue: RuntimePollQueue? = nil,
        providerId: String = "codex-cli"
    ) -> MainChatRustTransportProvider {
        let queue = queue ?? RuntimePollQueue(results: polls)
        let backend: MainChatProviderBackendBridge
        let displayName: String
        let claudePath: String?
        let codexPath: String?
        switch providerId {
        case "claude-cli":
            backend = .claudeCli
            displayName = "Claude"
            claudePath = "/usr/bin/claude"
            codexPath = nil
        default:
            backend = .codexCli
            displayName = "Codex"
            claudePath = nil
            codexPath = "/usr/bin/codex"
        }
        return MainChatRustTransportProvider(
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
                codexPath: codexPath,
                codexSandbox: "workspace-write",
                codexAskForApproval: "never",
                codexModelOverride: nil,
                codexReasoningEffort: nil,
                codexModelProvider: nil,
                codexFastMode: false,
                codexSessionFullAccess: false,
                codexPreferResponsesWireAPI: false,
                claudePath: claudePath,
                claudeModel: nil,
                claudeAllowedTools: [],
                claudeMcpServerPath: nil,
                geminiCliPath: nil,
                geminiModelOverride: nil,
                attachments: [],
                cliAccounts: []
            ),
            startSessionBridge: { _ in .init(schemaVersion: 1, error: nil, snapshot: nil, events: []) },
            pollSessionBridge: { _ in nil },
            cancelSessionBridge: { _ in nil },
            runtimePollBridge: { request in queue.next(for: request) }
        )
    }
}

private struct RuntimePollResult {
    let textByStreamId: [String: String]
    let signals: [MainChatRuntimeSignalKindBridge]
    let uiEvents: [MainChatRuntimeUIEventBridge]
    let status: String
    let terminalError: String?
    let shouldRetryPoll: Bool
    let didTimeout: Bool
    let isTerminal: Bool

    init(
        textByStreamId: [String: String],
        signals: [MainChatRuntimeSignalKindBridge] = [],
        uiEvents: [MainChatRuntimeUIEventBridge],
        status: String = "streaming",
        terminalError: String? = nil,
        shouldRetryPoll: Bool = false,
        didTimeout: Bool = false,
        isTerminal: Bool = false
    ) {
        self.textByStreamId = textByStreamId
        self.signals = signals
        self.uiEvents = uiEvents
        self.status = status
        self.terminalError = terminalError
        self.shouldRetryPoll = shouldRetryPoll
        self.didTimeout = didTimeout
        self.isTerminal = isTerminal
    }
}

private final class RuntimePollQueue {
    private var results: [RuntimePollResult]
    private var handlers: [(MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse]

    init(results: [RuntimePollResult] = []) {
        self.results = results
        self.handlers = []
    }

    func enqueue(
        _ handler: @escaping (MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse
    ) {
        handlers.append(handler)
    }

    func next(for request: MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse? {
        if !handlers.isEmpty {
            return handlers.removeFirst()(request)
        }
        guard !results.isEmpty else { return nil }
        let result = results.removeFirst()
        let snapshot = MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(
                conversationId: request.snapshot.turnState.conversationId,
                assistantMessageId: request.snapshot.turnState.assistantMessageId,
                turnId: request.snapshot.turnState.turnId,
                providerId: request.snapshot.turnState.providerId,
                sequence: request.snapshot.turnState.sequence,
                isStreaming: result.status == "streaming",
                startedAt: request.snapshot.turnState.startedAt,
                completedAt: result.isTerminal ? Date() : request.snapshot.turnState.completedAt,
                updatedAt: Date(),
                status: result.status,
                orderedTextStreamIds: result.textByStreamId.isEmpty ? request.snapshot.turnState.orderedTextStreamIds : ["main"],
                textByStreamId: result.textByStreamId.isEmpty ? request.snapshot.turnState.textByStreamId : result.textByStreamId,
                reasoningByGroupId: request.snapshot.turnState.reasoningByGroupId,
                artifacts: request.snapshot.turnState.artifacts
            ),
            mode: request.snapshot.mode,
            directStream: {
                var direct = request.snapshot.directStream
                let receivedAnyEvent = direct?.hasReceivedAnyEvent == true || !result.uiEvents.isEmpty
                let emittedFirstText = direct?.emittedFirstText == true
                    || result.uiEvents.contains { $0.kind == .textDelta || $0.kind == .textReplace }
                direct?.hasReceivedAnyEvent = receivedAnyEvent
                direct?.emittedFirstText = emittedFirstText
                return direct
            }(),
            plan: request.snapshot.plan,
            output: MainChatRuntimeOutputBridge(
                chatContentOverride: nil,
                shouldHidePlanMarkdown: request.snapshot.output?.shouldHidePlanMarkdown ?? false,
                shouldOpenPlanPanel: request.snapshot.output?.shouldOpenPlanPanel ?? false,
                shouldFinalizeStream: result.isTerminal,
                shouldRetryPoll: result.shouldRetryPoll,
                followUpPrompt: nil,
                generatedPrompt: nil,
                terminalError: result.terminalError
            )
        )
        return MainChatRuntimeProviderPollBridgeResponse(
            schemaVersion: 1,
            error: nil,
            runtimeSnapshot: snapshot,
            signals: result.signals,
            uiEvents: result.uiEvents,
            isTerminal: result.isTerminal,
            didTimeout: result.didTimeout
        )
    }
}
