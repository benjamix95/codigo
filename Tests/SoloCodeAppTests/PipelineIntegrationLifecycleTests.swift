import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationLifecycleTests: XCTestCase {
    func testTaskLifecycleEmitsChatArtifactsAndConcreteActivities() async throws {
        let suiteName = "PipelineIntegrationLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

        let conversationId = try XCTUnwrap(chatStore.conversations.first?.id)
        let assistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: assistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: conversationId
        )

        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        service.executeJob(
            PipelineJob(
                jobId: "job-lifecycle",
                workspace: "/tmp",
                request: "Test lifecycle"
            ),
            tasks: [TaskNode(taskId: "task-1", title: "Run lifecycle step")],
            workerAdapter: AgentWorkerAdapter(
                provider: SlowLifecycleMockProvider(),
                context: context,
                jobId: "job-lifecycle"
            ),
            providerId: "provider-lifecycle",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )

        service.handleEvent(
            .taskStarted(
                TaskStartedPayload(
                    jobId: "job-lifecycle",
                    taskId: "task-1",
                    title: "Run lifecycle step",
                    agentName: "Coder",
                    role: .coder
                )
            ),
            for: conversationId
        )
        service.handleEvent(
            .taskCompleted(
                TaskCompletedPayload(
                    jobId: "job-lifecycle",
                    taskId: "task-1",
                    title: "Run lifecycle step",
                    agentName: "Coder",
                    role: .coder,
                    durationMs: 42
                )
            ),
            for: conversationId
        )

        taskActivityStore.flushPending()

        let concreteTypes = Set(taskActivityStore.concreteRecentActivities(limit: 10).map(\.type))
        XCTAssertTrue(concreteTypes.contains("pipeline_task_started"))
        XCTAssertTrue(concreteTypes.contains("pipeline_task_completed"))

        let blocks = chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.id == assistantMessageId })?
            .resolvedTimelineBlocks ?? []
        let statusBlocks = blocks.filter { $0.kind == .status }

        XCTAssertTrue(statusBlocks.contains {
            ($0.title ?? "") == "Run lifecycle step" && $0.text.contains("in progress")
        })
        XCTAssertTrue(statusBlocks.contains {
            ($0.title ?? "") == "Run lifecycle step" && $0.text.contains("completed in 42ms")
        })

        XCTAssertTrue(service.discardConversationRuntime(for: conversationId))
    }

    func testDiscardConversationRuntimeStopsTrackingImmediately() async throws {
        let suiteName = "PipelineIntegrationLifecycleDiscardTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

        let conversationId = try XCTUnwrap(chatStore.conversations.first?.id)
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        service.executeJob(
            PipelineJob(
                jobId: "job-discard",
                workspace: "/tmp",
                request: "Discard runtime"
            ),
            tasks: [TaskNode(taskId: "task-discard", title: "Long task")],
            workerAdapter: AgentWorkerAdapter(
                provider: SlowLifecycleMockProvider(delayNanoseconds: 2_000_000_000),
                context: context,
                jobId: "job-discard"
            ),
            providerId: "provider-discard",
            conversationId: conversationId,
            assistantMessageId: UUID()
        )

        XCTAssertTrue(service.isRunning(for: conversationId))
        XCTAssertTrue(chatStore.isTaskActive(for: conversationId))

        XCTAssertTrue(service.discardConversationRuntime(for: conversationId))
        XCTAssertFalse(service.isRunning(for: conversationId))
        XCTAssertNil(service.snapshot(for: conversationId))
        XCTAssertFalse(chatStore.isTaskActive(for: conversationId))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(service.isRunning(for: conversationId))
    }

    func testExecuteJobReplacesExistingRunningRuntimeForSameConversation() async throws {
        let suiteName = "PipelineIntegrationLifecycleReplaceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

        let conversationId = try XCTUnwrap(chatStore.conversations.first?.id)
        let firstAssistantMessageId = UUID()
        let secondAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(id: firstAssistantMessageId, role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )
        chatStore.addMessage(
            ChatMessage(id: secondAssistantMessageId, role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )

        let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
        service.executeJob(
            PipelineJob(jobId: "job-first", workspace: "/tmp", request: "First job"),
            tasks: [TaskNode(taskId: "task-first", title: "First task")],
            workerAdapter: AgentWorkerAdapter(
                provider: SlowLifecycleMockProvider(delayNanoseconds: 2_000_000_000),
                context: context,
                jobId: "job-first"
            ),
            providerId: "provider-first",
            conversationId: conversationId,
            assistantMessageId: firstAssistantMessageId
        )

        XCTAssertEqual(service.snapshot(for: conversationId)?.assistantMessageId, firstAssistantMessageId)
        XCTAssertTrue(service.isRunning(for: conversationId))

        service.executeJob(
            PipelineJob(jobId: "job-second", workspace: "/tmp", request: "Second job"),
            tasks: [TaskNode(taskId: "task-second", title: "Second task")],
            workerAdapter: AgentWorkerAdapter(
                provider: SlowLifecycleMockProvider(delayNanoseconds: 2_000_000_000),
                context: context,
                jobId: "job-second"
            ),
            providerId: "provider-second",
            conversationId: conversationId,
            assistantMessageId: secondAssistantMessageId
        )

        XCTAssertEqual(service.snapshot(for: conversationId)?.assistantMessageId, secondAssistantMessageId)
        XCTAssertEqual(service.providerId(for: conversationId), "provider-second")
        XCTAssertTrue(service.isRunning(for: conversationId))
        XCTAssertTrue(chatStore.isTaskActive(for: conversationId))

        XCTAssertTrue(service.cancelCurrentJob(for: conversationId))
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(service.isRunning(for: conversationId))
    }
}

private final class SlowLifecycleMockProvider: LLMProvider, @unchecked Sendable {
    let id = "slow-lifecycle-mock"
    let displayName = "SlowLifecycleMock"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 500_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let delayNanoseconds = self.delayNanoseconds
        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
