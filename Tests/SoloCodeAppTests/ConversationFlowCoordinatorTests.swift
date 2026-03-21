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
        let provider = MockStreamingProvider(events: [
            .started,
            .textDelta("Ciao"),
            .textDelta(" mondo"),
            .completed,
        ])
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
        var events: [StreamEvent] = [.started]
        for idx in 0..<250 {
            events.append(.raw(type: "command_execution", payload: [
                "id": "cmd-\(idx)",
                "status": "in_progress"
            ]))
        }
        events.append(.textDelta("Final output"))
        events.append(.completed)

        let provider = MockStreamingProvider(events: events)
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

    func testRunStreamCanExecuteOffMainActorWhileDispatchingCallbacksOnMain() async throws {
        let result = try await Task.detached { () throws -> (String, ConversationFlowCoordinator.State) in
            let provider = MockStreamingProvider(events: [
                .started,
                .raw(type: "command_execution", payload: ["id": "cmd-1", "status": "started"]),
                .textDelta("ok"),
                .completed,
            ])
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
        let provider = MockStreamingProvider(events: [
            .started,
            .textDelta("partial"),
            .error("boom"),
            .completed,
        ])
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
        let provider = MockStreamingProvider(scheduledEvents: [
            ScheduledStreamEvent(delayNanoseconds: 1_200_000_000, event: .textDelta("late")),
            ScheduledStreamEvent(delayNanoseconds: 0, event: .completed),
        ])
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

        let provider = MockStreamingProvider(events: [.started, .textDelta("ciao"), .completed])
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
}

private struct ScheduledStreamEvent: Sendable {
    let delayNanoseconds: UInt64
    let event: StreamEvent
}

private final class MockStreamingProvider: LLMProvider, @unchecked Sendable {
    let id: String = "mock-stream"
    let displayName: String = "Mock Stream"

    private let scheduledEvents: [ScheduledStreamEvent]

    init(events: [StreamEvent]) {
        self.scheduledEvents = events.map { ScheduledStreamEvent(delayNanoseconds: 0, event: $0) }
    }

    init(scheduledEvents: [ScheduledStreamEvent]) {
        self.scheduledEvents = scheduledEvents
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let scheduledEvents = self.scheduledEvents
        return AsyncThrowingStream { continuation in
            Task {
                for item in scheduledEvents {
                    if item.delayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: item.delayNanoseconds)
                    }
                    continuation.yield(item.event)
                }
                continuation.finish()
            }
        }
    }
}

private final class RuntimePollQueue {
    private var handlers: [(MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse] = []

    func enqueue(_ handler: @escaping (MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse) {
        handlers.append(handler)
    }

    func next(for request: MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse? {
        guard !handlers.isEmpty else { return nil }
        return handlers.removeFirst()(request)
    }
}
