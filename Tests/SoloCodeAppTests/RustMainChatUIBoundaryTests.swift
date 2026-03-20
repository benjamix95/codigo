import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatUIBoundaryTests: XCTestCase {
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
    func testProjectUIDecodesSelectedConversationFromRustBoundary() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let state = makeUIState()
        let snapshot = try XCTUnwrap(RustMainChatStoreAdapter.projectUI(state))
        XCTAssertEqual(snapshot.selectedConversationId, state.selectedConversationId)
        XCTAssertEqual(snapshot.messages.first?.primaryText, "Hello from Rust")
        XCTAssertTrue(snapshot.task.isLoading)
    }

    @MainActor
    func testHandleUIIntentTogglesCollapsedArtifactState() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let response = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "toggle_artifact_collapsed",
                    state: makeUIState(),
                    conversationId: nil,
                    turnId: "turn-1",
                    artifactId: "artifact-1",
                    text: nil,
                    timestamp: nil,
                    payload: [:]
                )
            )
        )
        XCTAssertEqual(response.state?.collapsedArtifactIdsByTurn["turn-1"], ["artifact-1"])
    }

    @MainActor
    func testApplyUIIntentSyncsRuntimeTextIntoChatStore() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let suiteName = "RustMainChatUIBoundaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ChatStore(userDefaults: defaults)
        let state = makeUIState()
        RustMainChatStoreAdapter.apply(snapshot: state.storeSnapshot, to: store)
        let response = try XCTUnwrap(
            RustMainChatStoreAdapter.applyUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "stream_replace_text",
                    state: state,
                    conversationId: state.selectedConversationId,
                    turnId: nil,
                    artifactId: nil,
                    text: "ignored",
                    timestamp: nil,
                    payload: [:]
                ),
                to: store
            )
        )
        XCTAssertNotNil(response.snapshot)
        XCTAssertEqual(store.conversations.first?.messages.first?.primaryTextSnapshot, "Hello from Rust")
    }

    @MainActor
    func testApplyUIIntentFinishSuccessShowsFinalActions() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let suiteName = "RustMainChatUIBoundaryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ChatStore(userDefaults: defaults)
        let state = makeUIState()
        RustMainChatStoreAdapter.apply(snapshot: state.storeSnapshot, to: store)

        _ = try XCTUnwrap(
            RustMainChatStoreAdapter.applyUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "stream_finish_success",
                    state: state,
                    conversationId: state.selectedConversationId,
                    turnId: nil,
                    artifactId: nil,
                    text: "Final answer",
                    timestamp: Date(),
                    payload: [:]
                ),
                to: store
            )
        )

        let conversation = try XCTUnwrap(store.conversations.first)
        XCTAssertEqual(conversation.messages.first?.primaryTextSnapshot, "Final answer")
        XCTAssertFalse(conversation.messages.first?.isStreaming ?? true)
        XCTAssertTrue(
            ChatPanelView.shouldShowFinalChatActions(
                conversation: conversation,
                isLoadingForCurrentConversation: false
            )
        )
    }

    private func makeUIState() -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: MainChatStoreSnapshotBridge(
                conversations: [
                    MainChatStoreConversationSnapshotBridge(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        threadRootConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        title: "Main",
                        messages: [
                            MainChatStoreMessageSnapshotBridge(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!.uuidString.lowercased(),
                                role: "assistant",
                                content: "Hello",
                                primaryTextSnapshot: "Hello",
                                blocks: nil,
                                turnMetadata: nil,
                                isStreaming: true,
                                imagePaths: nil,
                                attachments: nil,
                                planAttachment: nil,
                                reasoningText: nil,
                                subagentCards: nil
                            )
                        ],
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
            runtimeSnapshot: MainChatRuntimeSnapshotBridge(
                turnState: MainChatBridgeState(
                    conversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    assistantMessageId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    turnId: "turn-1",
                    providerId: "codex-cli",
                    sequence: 1,
                    isStreaming: true,
                    startedAt: Date(timeIntervalSinceReferenceDate: 10),
                    completedAt: nil,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 10),
                    status: "streaming",
                    orderedTextStreamIds: ["main"],
                    textByStreamId: ["main": "Hello from Rust"],
                    reasoningByGroupId: [:],
                    artifacts: [
                        ChatArtifact(
                            id: "artifact-1",
                            kind: .status,
                            title: "Status",
                            text: "Running",
                            items: [],
                            metadata: [:],
                            isCollapsible: true,
                            isCollapsedByDefault: false
                        )
                    ]
                ),
                mode: .directStream,
                directStream: nil,
                plan: nil,
                output: MainChatRuntimeOutputBridge(
                    chatContentOverride: nil,
                    shouldHidePlanMarkdown: false,
                    shouldOpenPlanPanel: false,
                    shouldFinalizeStream: false,
                    shouldRetryPoll: false,
                    followUpPrompt: nil,
                    generatedPrompt: nil,
                    terminalError: nil
                )
            ),
            taskRuntimeState: MainChatTaskRuntimeStateBridge(
                taskStates: [
                    MainChatTaskStateSnapshotBridge(
                        conversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        startedAt: Date(timeIntervalSinceReferenceDate: 10),
                        statusText: "Running"
                    )
                ]
            ),
            selectedConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
            draftText: "continue",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:],
            autoTodoRuntimeStateByMessage: [:]
        )
    }
}
