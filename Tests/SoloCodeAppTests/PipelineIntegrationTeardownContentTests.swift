import XCTest
@testable import CoderIDE
import CoderEngine

/// Regressione: il contenuto assistente deve restare visibile nello store
/// dopo `finalizeExecution` (claimTeardownRuntime + completeTeardown).
/// Il bug originale: il testo era visibile solo durante lo streaming (overlay)
/// e spariva quando il runtime veniva rimosso, rendendo necessario un restart.
@MainActor
final class PipelineIntegrationTeardownContentTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        chatStore: ChatStore,
        todoStore: TodoStore
    ) -> PipelineIntegrationService {
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
        return service
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "TeardownContentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: - Tests

    func testFinalizeExecutionPreservesAssistantContentInStore() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let service = makeService(chatStore: chatStore, todoStore: todoStore)

        let conversationId = chatStore.conversations[0].id
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
                jobId: "job-teardown-content",
                workspace: "/tmp",
                request: "Test teardown content"
            ),
            tasks: [TaskNode(taskId: "task-1", title: "Step")],
            workerAdapter: AgentWorkerAdapter(
                provider: TeardownContentMockProvider(),
                context: context,
                jobId: "job-teardown-content"
            ),
            providerId: "provider-teardown",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )

        // Simula textDelta durante streaming
        service.consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: "turn-1",
                    sequence: 1,
                    source: "provider-teardown",
                    kind: .textDelta,
                    payload: ["delta": "Ecco la risposta completa del modello."]
                ),
            ],
            for: conversationId
        )

        // Simula turnCompleted
        service.consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: "turn-1",
                    sequence: 2,
                    source: "provider-teardown",
                    kind: .turnCompleted,
                    payload: ["status": "completed"]
                ),
            ],
            for: conversationId
        )

        // Verifica pre-teardown: il runtime esiste ancora
        XCTAssertTrue(service.isRunning(for: conversationId))

        // Simula finalizeExecution (claimTeardownRuntime + completeTeardown)
        service.finalizeExecution(for: conversationId)

        // Verifica post-teardown: runtime rimosso
        XCTAssertFalse(service.isRunning(for: conversationId))
        XCTAssertNil(service.snapshot(for: conversationId))
        XCTAssertFalse(chatStore.isTaskActive(for: conversationId))

        // REGRESSIONE: il contenuto deve essere nello store dopo teardown
        let conversation = chatStore.conversation(for: conversationId)
        let assistantMessage = conversation?.messages.first(where: {
            $0.id == assistantMessageId
        })

        XCTAssertNotNil(assistantMessage, "Il messaggio assistente deve esistere nello store")

        let resolvedText = assistantMessage?.resolvedPrimaryText ?? ""
        XCTAssertFalse(
            resolvedText.isEmpty,
            "resolvedPrimaryText non deve essere vuoto dopo teardown"
        )
        XCTAssertTrue(
            resolvedText.contains("Ecco la risposta"),
            "Il contenuto del textDelta deve essere preservato: '\(resolvedText)'"
        )

        // Il messaggio non deve più essere in streaming
        XCTAssertEqual(assistantMessage?.isStreaming, false)

        // I blocchi devono contenere almeno un primaryText
        let blocks = assistantMessage?.resolvedTimelineBlocks ?? []
        let primaryBlocks = blocks.filter { $0.kind == .primaryText }
        XCTAssertFalse(
            primaryBlocks.isEmpty,
            "Deve esserci almeno un blocco primaryText dopo teardown"
        )
        let primaryText = primaryBlocks.map(\.text).joined()
        XCTAssertTrue(
            primaryText.contains("Ecco la risposta"),
            "Il blocco primaryText deve contenere il testo: '\(primaryText)'"
        )
    }

    func testFinalizeExecutionFlushesThrottledNotification() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let chatStore = ChatStore(userDefaults: defaults)
        let todoStore = TodoStore(
            storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)",
            userDefaults: defaults
        )
        let service = makeService(chatStore: chatStore, todoStore: todoStore)

        let conversationId = chatStore.conversations[0].id
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
                jobId: "job-flush",
                workspace: "/tmp",
                request: "Test flush"
            ),
            tasks: [TaskNode(taskId: "task-flush", title: "Flush step")],
            workerAdapter: AgentWorkerAdapter(
                provider: TeardownContentMockProvider(),
                context: context,
                jobId: "job-flush"
            ),
            providerId: "provider-flush",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )

        // Streaming text
        service.consumePipelineEvents(
            [
                ChatPipelineEvent(
                    conversationId: conversationId,
                    assistantMessageId: assistantMessageId,
                    turnId: "turn-flush",
                    sequence: 1,
                    source: "provider-flush",
                    kind: .textDelta,
                    payload: ["delta": "Contenuto di test."]
                ),
            ],
            for: conversationId
        )

        // Conta le notifiche objectWillChange DOPO il teardown
        var notificationCount = 0
        let cancellable = chatStore.objectWillChange.sink { _ in
            notificationCount += 1
        }

        service.finalizeExecution(for: conversationId)

        // Deve aver ricevuto almeno una notifica (flush dalla nostra fix)
        XCTAssertGreaterThan(
            notificationCount, 0,
            "completeTeardown deve inviare almeno una notifica post-rimozione runtime"
        )

        cancellable.cancel()
    }
}

private final class TeardownContentMockProvider: LLMProvider, @unchecked Sendable {
    let id = "teardown-content-mock"
    let displayName = "TeardownContentMock"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none

    func isAuthenticated() -> Bool { true }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }
}
