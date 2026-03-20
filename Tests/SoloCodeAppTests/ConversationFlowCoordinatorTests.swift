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
