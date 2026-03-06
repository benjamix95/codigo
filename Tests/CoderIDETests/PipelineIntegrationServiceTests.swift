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
            "target_path": "/tmp/Codigo.app",
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
        XCTAssertEqual(debugStore.nativeTargetPathInput, "/tmp/Codigo.app")
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
