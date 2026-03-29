import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationTodoBatchTests: XCTestCase {
    func testRawTodoWriteBatchWithoutItemIDsCreatesDistinctRuntimeTodos() {
        let suiteName = "PipelineIntegrationTodoBatchTests.\(UUID().uuidString)"
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

        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        service.executeJob(
            makeJob(id: "job-todo-batch"),
            tasks: [TaskNode(taskId: "task-todo-batch", title: "Batch todo")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedTodoBatchProvider(
                    id: "provider-todo-batch",
                    text: "ok",
                    delayNanoseconds: 500_000_000
                ),
                context: context,
                jobId: "job-todo-batch"
            ),
            providerId: "provider-todo-batch",
            conversationId: conversationId,
            assistantMessageId: UUID()
        )

        let sharedTaskId = UUID().uuidString
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-todo-batch",
                taskId: sharedTaskId,
                rawType: "todo_write",
                payload: [
                    "todos_json": #"[{"content":"Step A","status":"pending"},{"content":"Step B","status":"pending"}]"#,
                ]
            ),
            for: conversationId
        )

        let created = todoStore.todos.filter { ["Step A", "Step B"].contains($0.title) }
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(Set(created.map(\.title)), Set(["Step A", "Step B"]))
        XCTAssertEqual(Set(created.map(\.id)).count, 2)
        XCTAssertTrue(created.allSatisfy { $0.planConversationId == conversationId })

        XCTAssertTrue(service.cancelCurrentJob(for: conversationId))
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

private final class DelayedTodoBatchProvider: LLMProvider, @unchecked Sendable {
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
