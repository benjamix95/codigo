import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatAutoTodoBoundaryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    @MainActor
    func testBeginRecordAndFinalizeApplyAutoTodoPatches() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }

        let defaults = UserDefaults(suiteName: "RustMainChatAutoTodoBoundaryTests.\(UUID().uuidString)")!
        let todoStore = TodoStore(storageKey: "todo.\(UUID().uuidString)", userDefaults: defaults)
        let begin = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "auto_todo_begin_runtime",
                    state: makeUIState(),
                    conversationId: "00000000-0000-0000-0000-000000000001",
                    turnId: nil,
                    artifactId: nil,
                    text: nil,
                    timestamp: Date(),
                    payload: [
                        "assistant_message_id": "00000000-0000-0000-0000-000000000002",
                        "provider_id": "codex-cli",
                        "path": "Sources/App.swift",
                        "immediate_label": "Editing code",
                    ]
                )
            )
        )
        MainChatTodoPatchAdapter.apply(begin.todoPatches, to: todoStore)
        let startedTodo = try XCTUnwrap(todoStore.todos.first)
        XCTAssertEqual(startedTodo.title, "Complete changes on App.swift")
        XCTAssertEqual(startedTodo.status, .inProgress)

        let record = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "auto_todo_record_operation",
                    state: try XCTUnwrap(begin.state),
                    conversationId: "00000000-0000-0000-0000-000000000001",
                    turnId: nil,
                    artifactId: nil,
                    text: nil,
                    timestamp: Date(),
                    payload: [
                        "assistant_message_id": "00000000-0000-0000-0000-000000000002",
                        "provider_id": "codex-cli",
                        "file": "Tests/AppTests.swift",
                        "immediate_label": "Editing code",
                    ]
                )
            )
        )
        MainChatTodoPatchAdapter.apply(record.todoPatches, to: todoStore)
        let updatedTodo = try XCTUnwrap(todoStore.todos.first)
        XCTAssertEqual(updatedTodo.id, startedTodo.id)
        XCTAssertEqual(updatedTodo.activeForm, "Editing code")
        XCTAssertEqual(updatedTodo.notes, "Auto-generated: tracking live operational activity until the agent publishes an explicit todo.")

        let finalize = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "auto_todo_finalize_runtime",
                    state: try XCTUnwrap(record.state),
                    conversationId: "00000000-0000-0000-0000-000000000001",
                    turnId: nil,
                    artifactId: nil,
                    text: nil,
                    timestamp: Date(),
                    payload: [
                        "assistant_message_id": "00000000-0000-0000-0000-000000000002",
                        "provider_id": "codex-cli",
                        "outcome": "success",
                    ]
                )
            )
        )
        MainChatTodoPatchAdapter.apply(finalize.todoPatches, to: todoStore)
        XCTAssertEqual(todoStore.todos.first?.status, .done)
        XCTAssertTrue(try XCTUnwrap(finalize.state).autoTodoRuntimeStateByMessage.isEmpty)
    }

    @MainActor
    func testDiscardRemovesAutoTodo() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }

        let defaults = UserDefaults(suiteName: "RustMainChatAutoTodoBoundaryTests.\(UUID().uuidString)")!
        let todoStore = TodoStore(storageKey: "todo.\(UUID().uuidString)", userDefaults: defaults)
        let begin = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "auto_todo_begin_runtime",
                    state: makeUIState(),
                    conversationId: "00000000-0000-0000-0000-000000000001",
                    turnId: nil,
                    artifactId: nil,
                    text: nil,
                    timestamp: Date(),
                    payload: [
                        "assistant_message_id": "00000000-0000-0000-0000-000000000002",
                        "provider_id": "codex-cli",
                        "command": "rg TODO Sources/",
                    ]
                )
            )
        )
        MainChatTodoPatchAdapter.apply(begin.todoPatches, to: todoStore)
        XCTAssertEqual(todoStore.todos.count, 1)

        let discard = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "auto_todo_discard_runtime",
                    state: try XCTUnwrap(begin.state),
                    conversationId: "00000000-0000-0000-0000-000000000001",
                    turnId: nil,
                    artifactId: nil,
                    text: nil,
                    timestamp: Date(),
                    payload: [
                        "assistant_message_id": "00000000-0000-0000-0000-000000000002",
                        "provider_id": "codex-cli",
                    ]
                )
            )
        )
        MainChatTodoPatchAdapter.apply(discard.todoPatches, to: todoStore)
        XCTAssertTrue(todoStore.todos.isEmpty)
        XCTAssertTrue(try XCTUnwrap(discard.state).autoTodoRuntimeStateByMessage.isEmpty)
    }

    private func makeUIState() -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: MainChatStoreSnapshotBridge(
                conversations: [
                    MainChatStoreConversationSnapshotBridge(
                        id: "00000000-0000-0000-0000-000000000001",
                        threadRootConversationId: "00000000-0000-0000-0000-000000000001",
                        title: "Main",
                        messages: [],
                        createdAt: nil,
                        contextId: nil,
                        contextFolderPath: nil,
                        mode: "Agent",
                        preferredProviderId: "codex-cli",
                        contextMemorySummaryMarkdown: nil,
                        contextMemoryGeneratedAt: nil,
                        contextMemorySourceMessageCount: nil,
                        isArchived: false,
                        isPinned: false,
                        isFavorite: false,
                        lastInputTokens: nil,
                        workspaceId: nil,
                        adHocFolderPaths: [],
                        checkpoints: []
                    )
                ],
                planBoards: [:]
            ),
            runtimeSnapshot: nil,
            taskRuntimeState: nil,
            selectedConversationId: "00000000-0000-0000-0000-000000000001",
            draftText: "",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:],
            autoTodoRuntimeStateByMessage: [:]
        )
    }
}
