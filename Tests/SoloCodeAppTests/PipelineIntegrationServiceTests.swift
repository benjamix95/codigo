import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class PipelineIntegrationServiceTests: XCTestCase {
    func testHandleTaskCompletedMarksCanonicalTodoDoneForReviewerAndTestWriter() async {
        for role in [AgentRole.reviewer, .testWriter] {
            let suiteName = "PipelineIntegrationServiceTests.review.\(role.rawValue).\(UUID().uuidString)"
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

            let agentConversationId = chatStore.conversations[0].id
            let planConversationId = chatStore.createConversation(
                contextId: nil,
                contextFolderPath: nil,
                mode: .plan
            )
            chatStore.addMessage(
                ChatMessage(role: .assistant, content: "", isStreaming: true),
                to: agentConversationId
            )

            todoStore.upsertCanonicalPlanTodos(
                ["Code Review & Test"],
                conversationId: planConversationId
            )

            let context = WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")])
            service.executeJob(
                makeJob(id: "job-\(role.rawValue)"),
                tasks: [TaskNode(taskId: "task-\(role.rawValue)", title: "Code Review & Test")],
                workerAdapter: AgentWorkerAdapter(
                    provider: DelayedMockPipelineProvider(
                        id: "provider-\(role.rawValue)",
                        text: role.rawValue,
                        delayNanoseconds: 500_000_000
                    ),
                    context: context,
                    jobId: "job-\(role.rawValue)"
                ),
                providerId: "provider-\(role.rawValue)",
                conversationId: agentConversationId,
                assistantMessageId: UUID(),
                planConversationId: planConversationId
            )

            service.handleEvent(
                .taskCompleted(
                    TaskCompletedPayload(
                        jobId: "job-\(role.rawValue)",
                        taskId: "task-\(role.rawValue)",
                        title: "Code Review & Test",
                        agentName: role.displayName,
                        role: role,
                        durationMs: 42
                    )
                ),
                for: agentConversationId
            )

            let canonicalTodo = todoStore.canonicalTodos(for: planConversationId).first
            XCTAssertEqual(canonicalTodo?.status, .done, "Il ruolo \(role.rawValue) deve completare il todo canonico finale")

            XCTAssertTrue(service.cancelCurrentJob(for: agentConversationId))
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testHandleTaskCompletedDoesNotPersistImplicitSingleTaskAsTodo() {
        let suiteName = "PipelineIntegrationServiceTests.single-task.\(UUID().uuidString)"
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
            makeJob(id: "job-single"),
            tasks: [TaskNode(taskId: "task-single", title: "Correggi il timer chat")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedMockPipelineProvider(
                    id: "provider-single",
                    text: "ok",
                    delayNanoseconds: 500_000_000
                ),
                context: context,
                jobId: "job-single"
            ),
            providerId: "provider-single",
            conversationId: conversationId,
            assistantMessageId: UUID()
        )

        service.handleEvent(
            .jobStarted(
                JobStartedPayload(
                    jobId: "job-single",
                    mode: .fast,
                    taskCount: 1
                )
            ),
            for: conversationId
        )
        service.handleEvent(
            .taskCompleted(
                TaskCompletedPayload(
                    jobId: "job-single",
                    taskId: "task-single",
                    title: "Correggi il timer chat",
                    agentName: "Coder",
                    role: .coder,
                    durationMs: 42
                )
            ),
            for: conversationId
        )

        XCTAssertFalse(
            todoStore.todos.contains {
                $0.source == .agent && !$0.isPlanCanonical
            }
        )

        XCTAssertTrue(service.cancelCurrentJob(for: conversationId))
    }

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
            providerId: "provider-1",
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
            providerId: "provider-2",
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

    func testExecuteJobScopesRawCallbacksPerConversation() {
        let suiteName = "PipelineIntegrationServiceTests.raw-callbacks.\(UUID().uuidString)"
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
        var firstProviderIds: [String] = []
        var secondProviderIds: [String] = []

        service.executeJob(
            makeJob(id: "job-raw-1"),
            tasks: [TaskNode(taskId: "task-raw-1", title: "First raw task")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedMockPipelineProvider(
                    id: "provider-raw-1",
                    text: "uno",
                    delayNanoseconds: 500_000_000
                ),
                context: context,
                jobId: "job-raw-1"
            ),
            providerId: "provider-raw-1",
            conversationId: firstConversationId,
            assistantMessageId: UUID(),
            rawEventHandler: { _, _, providerId, _ in
                firstProviderIds.append(providerId)
            }
        )

        service.executeJob(
            makeJob(id: "job-raw-2"),
            tasks: [TaskNode(taskId: "task-raw-2", title: "Second raw task")],
            workerAdapter: AgentWorkerAdapter(
                provider: DelayedMockPipelineProvider(
                    id: "provider-raw-2",
                    text: "due",
                    delayNanoseconds: 500_000_000
                ),
                context: context,
                jobId: "job-raw-2"
            ),
            providerId: "provider-raw-2",
            conversationId: secondConversationId,
            assistantMessageId: UUID(),
            rawEventHandler: { _, _, providerId, _ in
                secondProviderIds.append(providerId)
            }
        )

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-raw-1",
                taskId: "task-raw-1",
                rawType: "reasoning",
                payload: [
                    "output": "First reasoning",
                    "group_id": "reasoning-first",
                ]
            ),
            for: firstConversationId
        )
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-raw-2",
                taskId: "task-raw-2",
                rawType: "reasoning",
                payload: [
                    "output": "Second reasoning",
                    "group_id": "reasoning-second",
                ]
            ),
            for: secondConversationId
        )

        XCTAssertEqual(firstProviderIds, ["provider-raw-1"])
        XCTAssertEqual(secondProviderIds, ["provider-raw-2"])
        XCTAssertEqual(service.providerId(for: firstConversationId), "provider-raw-1")
        XCTAssertEqual(service.providerId(for: secondConversationId), "provider-raw-2")

        XCTAssertTrue(service.cancelCurrentJob(for: firstConversationId))
        XCTAssertTrue(service.cancelCurrentJob(for: secondConversationId))
    }

    func testHandleRawDebugNativeSessionProjectsStateIntoDebugStore() throws {
        let suiteName = "PipelineIntegrationServiceTests.native.\(UUID().uuidString)"
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
        let debugStore = DebugStore()
        let conversationId = chatStore.conversations[0].id

        service.configure(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            executionController: executionController
        )
        service.registerDebugStore(debugStore, for: conversationId)

        let breakpoint = DebugNativeBreakpointSpec(
            id: UUID().uuidString,
            filePath: "Sources/App.swift",
            line: 42,
            condition: nil,
            isActive: true
        )
        let payload: [String: String] = [
            "action": "native_start",
            "status": "paused",
            "adapter": "lldb-dap",
            "target_path": "/tmp/Solo Code.app",
            "breakpoints_count": "1",
            "arguments_json": try encodeJSON(["--flag", "value"]),
            "watch_expressions_json": try encodeJSON(["counter", "state"]),
            "native_breakpoints_json": try encodeJSON([breakpoint]),
            "call_stack_json": try encodeJSON([NativeCallStackFrame(
                function: "main",
                filePath: "Sources/App.swift",
                line: 42
            )]),
            "watch_variables_json": try encodeJSON([NativeWatchVariable(
                expression: "counter",
                value: "1"
            )]),
            "last_command": "process launch --stop-at-entry",
            "detail": "Native debug session started.",
            "group_id": "task-native",
        ]

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-native",
                taskId: "task-native",
                rawType: "debug_native_session",
                payload: payload
            ),
            for: conversationId
        )

        XCTAssertEqual(debugStore.nativeSession.status, .paused)
        XCTAssertEqual(debugStore.nativeSession.adapter, "lldb-dap")
        XCTAssertEqual(debugStore.nativeTargetPathInput, "/tmp/Solo Code.app")
        XCTAssertEqual(debugStore.nativeArgumentsInput, "--flag, value")
        XCTAssertEqual(debugStore.nativeWatchExpressionsInput, "counter, state")
        XCTAssertEqual(debugStore.breakpoints.count, 1)
        XCTAssertEqual(debugStore.breakpoints.first?.filePath, "Sources/App.swift")

        taskActivityStore.flushPending()
        XCTAssertTrue(
            taskActivityStore.concreteRecentActivities(limit: 20).contains {
                $0.type == "debug_native_session"
            }
        )
    }

    private func makeJob(id: String) -> PipelineJob {
        PipelineJob(
            jobId: id,
            workspace: "/tmp",
            request: "Test request for \(id)",
            maxConcurrentWorkers: 1
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
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
