import XCTest
@testable import CoderEngine

final class PipelineFacadeTests: XCTestCase {
    func testExecuteJobFailsFastOnDuplicateTaskIds() async {
        let events = await collectEvents(
            tasks: [
                TaskNode(taskId: "dup-task", title: "First"),
                TaskNode(taskId: "dup-task", title: "Duplicate")
            ]
        )

        guard case .jobFailed(let payload)? = events.first else {
            return XCTFail("Expected immediate jobFailed event")
        }
        XCTAssertTrue(payload.reason.contains("Duplicate task id"))
        XCTAssertFalse(events.contains { if case .jobStarted = $0 { return true } else { return false } })
    }

    func testExecuteJobFailsFastOnMissingDependency() async {
        let events = await collectEvents(
            tasks: [
                TaskNode(taskId: "task-main", title: "Main", dependsOn: ["missing-task"])
            ]
        )

        guard case .jobFailed(let payload)? = events.first else {
            return XCTFail("Expected immediate jobFailed event")
        }
        XCTAssertTrue(payload.reason.contains("depends on missing task"))
        XCTAssertFalse(events.contains { if case .jobStarted = $0 { return true } else { return false } })
    }

    func testExecuteJobFailsFastOnCycle() async {
        let events = await collectEvents(
            tasks: [
                TaskNode(taskId: "task-a", title: "A", dependsOn: ["task-b"]),
                TaskNode(taskId: "task-b", title: "B", dependsOn: ["task-a"])
            ]
        )

        guard case .jobFailed(let payload)? = events.first else {
            return XCTFail("Expected immediate jobFailed event")
        }
        XCTAssertTrue(payload.reason.contains("Cyclic dependency detected"))
        XCTAssertFalse(events.contains { if case .jobStarted = $0 { return true } else { return false } })
    }

    private func collectEvents(tasks: [TaskNode]) async -> [PipelineUIEvent] {
        let facade = PipelineFacade(config: PipelineFacadeConfig(
            tickIntervalMs: 5,
            completionTimeoutMs: 100,
            maxDeliveryAttempts: 1,
            dlqCapacity: 8
        ))
        let adapter = AgentWorkerAdapter(
            provider: PipelineFacadeSilentProvider(),
            context: WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")]),
            jobId: "job-test"
        )
        let stream = await facade.executeJob(
            PipelineJob(jobId: "job-test", workspace: "/tmp", request: "Validate graph"),
            tasks: tasks,
            workerAdapter: adapter
        )

        var results: [PipelineUIEvent] = []
        for await event in stream {
            results.append(event)
        }
        return results
    }
}

private final class PipelineFacadeSilentProvider: LLMProvider, @unchecked Sendable {
    let id = "pipeline-facade-silent-provider"
    let displayName = "PipelineFacadeSilentProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}
