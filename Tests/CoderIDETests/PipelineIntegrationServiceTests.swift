import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationServiceTests: XCTestCase {
    func testExecuteJobTracksIndependentPipelineStatePerConversation() async throws {
        let suiteName = "PipelineIntegrationServiceTests.\(UUID().uuidString)"
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
        let service = PipelineIntegrationService(
            facadeConfig: PipelineFacadeConfig(
                tickIntervalMs: 10,
                completionTimeoutMs: 200,
                maxDeliveryAttempts: 1,
                dlqCapacity: 32
            )
        )
        service.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )

        let firstConversationId = chatStore.conversations[0].id
        let secondConversationId = chatStore.createConversation(
            contextId: nil,
            contextFolderPath: nil,
            mode: nil
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: firstConversationId
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: secondConversationId
        )

        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        service.executeJob(
            makeJob(id: "job-1"),
            tasks: [TaskNode(taskId: "task-1", title: "First task")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedMockPipelineProvider(
                    id: "provider-1",
                    text: "uno",
                    delayNanoseconds: 40_000_000
                ),
                context: context,
                jobId: "job-1"
            ),
            conversationId: firstConversationId,
            assistantMessageId: UUID()
        )

        service.executeJob(
            makeJob(id: "job-2"),
            tasks: [TaskNode(taskId: "task-2", title: "Second task")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedMockPipelineProvider(
                    id: "provider-2",
                    text: "due",
                    delayNanoseconds: 40_000_000
                ),
                context: context,
                jobId: "job-2"
            ),
            conversationId: secondConversationId,
            assistantMessageId: UUID()
        )

        XCTAssertTrue(service.isRunning(for: firstConversationId))
        XCTAssertTrue(service.isRunning(for: secondConversationId))
        XCTAssertEqual(service.snapshot(for: firstConversationId)?.currentJobId, "job-1")
        XCTAssertEqual(service.snapshot(for: secondConversationId)?.currentJobId, "job-2")
        XCTAssertTrue(chatStore.isTaskActive(for: firstConversationId))
        XCTAssertTrue(chatStore.isTaskActive(for: secondConversationId))

        XCTAssertTrue(service.cancelCurrentJob(for: firstConversationId))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(service.isRunning(for: firstConversationId))
        XCTAssertTrue(service.isRunning(for: secondConversationId))
        XCTAssertFalse(chatStore.isTaskActive(for: firstConversationId))
        XCTAssertTrue(chatStore.isTaskActive(for: secondConversationId))

        XCTAssertTrue(service.cancelCurrentJob(for: secondConversationId))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(service.isRunning(for: secondConversationId))
        XCTAssertFalse(chatStore.isTaskActive(for: secondConversationId))
    }

    private func makeJob(id: String) -> PipelineJob {
        PipelineJob(
            jobId: id,
            workspace: "/tmp",
            request: "Test request for \(id)",
            maxConcurrentWorkers: 1
        )
    }
}

private final class DelayedMockPipelineProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private let text: String
    private let delayNanoseconds: UInt64

    init(id: String, text: String, delayNanoseconds: UInt64) {
        self.id = id
        self.displayName = id
        self.text = text
        self.delayNanoseconds = delayNanoseconds
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let text = self.text
        let delayNanoseconds = self.delayNanoseconds
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                continuation.yield(.textDelta(text))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
