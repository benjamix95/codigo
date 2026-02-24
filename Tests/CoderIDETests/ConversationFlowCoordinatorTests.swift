import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class ConversationFlowCoordinatorTests: XCTestCase {
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
        XCTAssertEqual(result.fullText, "Ciao mondo")
        XCTAssertNil(result.pendingSwarmTask)
        XCTAssertEqual(coordinator.state, .completed)
    }

    func testRunStreamExtractsPendingSwarmTaskFromRawEvent() async throws {
        let provider = MockStreamingProvider(events: [
            .started,
            .raw(type: "coderide_invoke_swarm", payload: ["task": "Analizza bug streaming"]),
            .textDelta("Ricevuto"),
            .completed,
        ])
        let coordinator = ConversationFlowCoordinator()
        let ctx = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])

        let result = try await coordinator.runStream(
            provider: provider,
            prompt: "test",
            context: ctx,
            attachments: nil,
            onText: { _ in },
            onRaw: { _, _, _ in },
            onError: { _ in }
        )

        XCTAssertEqual(result.fullText, "Ricevuto")
        XCTAssertEqual(result.pendingSwarmTask, "Analizza bug streaming")
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
        events.append(.textDelta("Output finale"))
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
        XCTAssertEqual(snapshots.last, "Output finale")
        XCTAssertEqual(result.fullText, "Output finale")
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
                    XCTFail("onError non atteso")
                }
            )
            let state = await MainActor.run { coordinator.state }
            return (streamResult.fullText, state)
        }.value

        XCTAssertEqual(result.0, "ok")
        XCTAssertEqual(result.1, .completed)
    }
}

private final class MockStreamingProvider: LLMProvider, @unchecked Sendable {
    let id: String = "mock-stream"
    let displayName: String = "Mock Stream"

    private let events: [StreamEvent]

    init(events: [StreamEvent]) {
        self.events = events
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let events = self.events
        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
