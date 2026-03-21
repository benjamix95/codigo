import XCTest
@testable import CoderIDE
import CoderEngine

final class ChatPipelineReducerTests: XCTestCase {
    func testRustReducerMatchesSwiftReducerForOrderedTextAndArtifacts() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let conversationId = UUID()
        let assistantMessageId = UUID()
        let events = [
            ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 1,
                source: "pipeline",
                kind: .turnStarted,
                payload: ["status": "streaming"]
            ),
            ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 2,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-2", "delta": "second"]
            ),
            ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 3,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-1", "delta": "first "]
            ),
            ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 4,
                source: "pipeline",
                kind: .mermaidArtifact,
                payload: ["artifact_id": "mermaid-1", "title": "Flow", "code": "graph TD; A-->B;"]
            ),
        ]

        var swiftState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            orderedTextStreamIds: ["task-1", "task-2"]
        )
        var rustState = swiftState

        for event in events {
            swiftState = ChatPipelineReducer.apply(state: swiftState, event: event)
            guard let nextRustState = MainChatRustBridge.reduce(state: rustState, event: event) else {
                XCTFail("Bridge Rust main chat non disponibile")
                return
            }
            rustState = nextRustState
        }

        XCTAssertEqual(rustState, swiftState)
        XCTAssertEqual(rustState.primaryTextSnapshot, "first second")
        XCTAssertTrue(rustState.blocks.contains(where: { $0.kind == .mermaid }))
    }

    func testReducerMaintainsStablePrimaryTextOrderAcrossStreamIDs() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            orderedTextStreamIds: ["task-1", "task-2"]
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 1,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-2", "delta": "second"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 2,
                source: "pipeline",
                kind: .textDelta,
                payload: ["stream_id": "task-1", "delta": "first "]
            )
        )

        XCTAssertEqual(state.primaryTextSnapshot, "first second")
    }

    func testReducerKeepsMermaidAsArtifactInsteadOfReplacingPrimaryText() {
        let conversationId = UUID()
        let assistantMessageId = UUID()
        var state = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString
        )

        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 1,
                source: "codex",
                kind: .textReplace,
                payload: ["replacement": "Primary response", "stream_id": "main"]
            )
        )
        state = ChatPipelineReducer.apply(
            state: state,
            event: ChatPipelineEvent(
                conversationId: conversationId,
                assistantMessageId: assistantMessageId,
                turnId: assistantMessageId.uuidString,
                sequence: 2,
                source: "codex",
                kind: .mermaidArtifact,
                payload: ["artifact_id": "mermaid-1", "title": "Flow", "code": "graph TD; A-->B;"]
            )
        )

        XCTAssertEqual(state.primaryTextSnapshot, "Primary response")
        XCTAssertEqual(state.blocks.first?.kind, .primaryText)
        XCTAssertTrue(state.blocks.contains(where: { $0.kind == .mermaid }))
    }

    @MainActor
    func testPipelineProjectsAssistantUpdateIntoPrimaryTextWhileStreaming() {
        let (service, chatStore, conversationId, assistantMessageId, defaults, suiteName) = makeAssistantUpdateHarness()
        defer {
            _ = service.discardConversationRuntime(for: conversationId)
            defaults.removePersistentDomain(forName: suiteName)
        }

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-assistant-update",
                taskId: "task-assistant-update",
                rawType: "assistant_update",
                payload: ["output": "Risposta inline dal raw assistant update", "group_id": "assistant-update-1"]
            ),
            for: conversationId
        )

        let message = chatStore.conversation(for: conversationId)?.messages.last(where: { $0.id == assistantMessageId })
        XCTAssertEqual(message?.primaryTextSnapshot, "Risposta inline dal raw assistant update")
    }

    @MainActor
    func testCompletedPipelineIgnoresLateAssistantUpdateOverwrite() {
        let (service, chatStore, conversationId, assistantMessageId, defaults, suiteName) = makeAssistantUpdateHarness()
        defer {
            _ = service.discardConversationRuntime(for: conversationId)
            defaults.removePersistentDomain(forName: suiteName)
        }

        service.handleEvent(.textReplace(.init(jobId: "job-assistant-update", taskId: "task-assistant-update", replacement: "Risposta finale confermata")), for: conversationId)
        service.handleEvent(.jobCompleted(.init(jobId: "job-assistant-update", durationMs: 42, completedTasks: 1, totalTasks: 1)), for: conversationId)
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-assistant-update",
                taskId: "task-assistant-update",
                rawType: "assistant_update",
                payload: ["output": "Aggiornamento tardivo che non deve vincere", "group_id": "assistant-update-late"]
            ),
            for: conversationId
        )

        let message = chatStore.conversation(for: conversationId)?.messages.last(where: { $0.id == assistantMessageId })
        XCTAssertEqual(message?.primaryTextSnapshot, "Risposta finale confermata")
    }

    @MainActor
    private func makeAssistantUpdateHarness() -> (PipelineIntegrationService, ChatStore, UUID, UUID, UserDefaults, String) {
        let suiteName = "ChatPipelineReducerTests.assistant-update.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let chatStore = ChatStore(userDefaults: defaults)
        let service = PipelineIntegrationService()
        service.configure(
            chatStore: chatStore,
            taskActivityStore: TaskActivityStore(),
            swarmProgressStore: SwarmProgressStore(),
            todoStore: TodoStore(storageKey: "CoderIDE.todos.tests.\(UUID().uuidString)", userDefaults: defaults),
            executionController: ExecutionController()
        )
        let conversationId = chatStore.conversations[0].id
        let assistantMessageId = UUID()
        chatStore.addMessage(ChatMessage(id: assistantMessageId, role: .assistant, content: "", isStreaming: true), to: conversationId)
        service.executeJob(
            PipelineJob(jobId: "job-assistant-update", workspace: "/tmp", request: "Assistant update fallback"),
            tasks: [TaskNode(taskId: "task-assistant-update", title: "Assistant update fallback")],
            workerAdapter: AgentWorkerAdapter(provider: IdlePipelineProvider(), context: WorkspaceContext(workspacePaths: [URL(fileURLWithPath: "/tmp")]), jobId: "job-assistant-update"),
            providerId: "provider-assistant-update",
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )
        return (service, chatStore, conversationId, assistantMessageId, defaults, suiteName)
    }
}

private final class IdlePipelineProvider: LLMProvider, @unchecked Sendable {
    let id = "idle-pipeline-provider"
    let displayName = "IdlePipelineProvider"
    let attachmentCapabilities: ProviderAttachmentCapabilities = .none
    func isAuthenticated() -> Bool { true }
    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in continuation.yield(.started) }
    }
}
