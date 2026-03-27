import CoderEngine
import XCTest
@testable import CoderIDE

@MainActor
final class PipelineIntegrationSnapshotTests: XCTestCase {
    func testUpdateSnapshotIfNeededReturnsFalseWhenRuntimeSnapshotIsUnchanged() async throws {
        let suiteName = "PipelineIntegrationSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let taskActivityStore = TaskActivityStore()
        let swarmProgressStore = SwarmProgressStore()
        let executionController = ExecutionController()
        let service = PipelineIntegrationService()
        service.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )

        let conversationId = chatStore.conversations[0].id
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )
        service.executeJob(
            PipelineJob(jobId: "job-snapshot", workspace: "/tmp", request: "noop", maxConcurrentWorkers: 1),
            tasks: [TaskNode(taskId: "task-snapshot", title: "Snapshot")],
            workerAdapter: AgentWorkerAdapter(
                provider: SnapshotMockProvider(),
                context: WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")]),
                jobId: "job-snapshot"
            ),
            providerId: "provider-snapshot",
            conversationId: conversationId,
            assistantMessageId: UUID()
        )

        let runtime = try XCTUnwrap(service.runtime(for: conversationId))
        let mutated = service.updateSnapshotIfNeeded(runtime.snapshot, for: conversationId)

        XCTAssertFalse(mutated)
        XCTAssertTrue(service.cancelCurrentJob(for: conversationId))
    }
}

private final class SnapshotMockProvider: LLMProvider, @unchecked Sendable {
    let id = "snapshot-mock"
    let displayName = "snapshot-mock"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continuation.finish()
            }
        }
    }
}
