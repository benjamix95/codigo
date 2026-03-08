import XCTest
@testable import CoderEngine

final class AgentWorkerAdapterDirectExecutionTests: XCTestCase {
    func testNativeCommandUsesDirectExecutorInsteadOfProvider() async {
        let provider = CountingLLMProvider()
        let directExecutor = MockDirectTaskExecutor()
        let adapter = AgentWorkerAdapter(
            provider: provider,
            context: WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")]),
            jobId: "job-native",
            directTaskExecutor: directExecutor
        )
        let task = TaskNode(
            taskId: "task-native",
            title: "Start Native Debug Session",
            executionStyle: .nativeCommand,
            debugStage: .nativeStart,
            metadata: ["backend_policy": DebugBackendPolicy.appleHybrid.rawValue]
        )

        let work = await adapter.makeWorkClosure(
            task: task,
            agentName: "native-debugger",
            role: .debugger
        )
        let result = await work()
        let executionCount = await directExecutor.executionCount

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.taskId, "task-native")
        XCTAssertEqual(provider.sendCallCount, 0)
        XCTAssertEqual(executionCount, 1)
    }

    func testPipelineFullPromptMetadataOverridesTaskTitle() async {
        let provider = CountingLLMProvider()
        let adapter = AgentWorkerAdapter(
            provider: provider,
            context: WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")]),
            jobId: "job-chat"
        )
        let fullPrompt = """
        Richiesta reale utente:
        analizza il bug della pipeline e proponi la fix completa.
        """
        let task = TaskNode(
            taskId: "task-chat",
            title: "Prompt troncato",
            metadata: ["pipeline_full_prompt": fullPrompt]
        )

        let work = await adapter.makeWorkClosure(
            task: task,
            agentName: "chat-coder",
            role: .coder
        )
        _ = await work()

        XCTAssertEqual(provider.sendCallCount, 1)
        XCTAssertEqual(provider.sentPrompts.count, 1)
        XCTAssertTrue(provider.sentPrompts[0].contains(fullPrompt))
        XCTAssertFalse(provider.sentPrompts[0].contains("## Task\nPrompt troncato"))
    }
}

private final class CountingLLMProvider: LLMProvider, @unchecked Sendable {
    let id = "counting-provider"
    let displayName = "Counting"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none
    private(set) var sendCallCount = 0
    private(set) var sentPrompts: [String] = []

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        sendCallCount += 1
        sentPrompts.append(prompt)
        return AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.textDelta(prompt))
            continuation.yield(.completed)
            continuation.finish()
        }
    }
}

private actor MockDirectTaskExecutor: PipelineDirectTaskExecutor {
    private(set) var executionCount = 0

    func canExecute(task: TaskNode) async -> Bool {
        task.executionStyle == .nativeCommand
    }

    func execute(
        task: TaskNode,
        agentName: String,
        role: AgentRole,
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        delegate: AgentWorkerDelegate?
    ) async -> WorkerTaskResult {
        executionCount += 1
        return WorkerTaskResult(
            taskId: task.taskId,
            agentName: agentName,
            agentRole: role,
            success: true,
            durationMs: 5,
            providerId: provider.id
        )
    }
}
