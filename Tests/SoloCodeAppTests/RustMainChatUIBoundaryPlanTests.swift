import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatUIBoundaryPlanTests: XCTestCase {
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
    func testApplyPlanIntentRaisesQuestionEpochAndOpensPanel() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let response = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "plan_receive_clarification_questions",
                    state: makePlanningUIState(),
                    conversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                    turnId: nil,
                    artifactId: nil,
                    text: "## Questions\n- Which flow moves first?",
                    timestamp: Date(),
                    payload: [:]
                )
            )
        )
        XCTAssertTrue(response.state?.planPanelVisible ?? false)
        XCTAssertEqual(response.snapshot?.plan.questionEpoch, 1)
        XCTAssertEqual(
            response.snapshot?.plan.clarificationQuestions,
            "## Questions\n- Which flow moves first?"
        )
    }

    private func makePlanningUIState() -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: MainChatStoreSnapshotBridge(
                conversations: [
                    MainChatStoreConversationSnapshotBridge(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        threadRootConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        title: "Main",
                        messages: [],
                        createdAt: nil,
                        contextId: nil,
                        contextFolderPath: nil,
                        mode: "Plan",
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
                    isStreaming: false,
                    startedAt: Date(timeIntervalSinceReferenceDate: 10),
                    completedAt: nil,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 10),
                    status: "idle",
                    orderedTextStreamIds: [],
                    textByStreamId: [:],
                    reasoningByGroupId: [:],
                    artifacts: []
                ),
                mode: .plan,
                directStream: nil,
                plan: MainChatPlanSnapshotBridge(
                    phase: .idle,
                    planningStateKind: .idle,
                    clarificationQuestions: nil,
                    proposalContent: nil,
                    optionFullTexts: [],
                    userRequest: "Ship Rust planning boundary",
                    analysisContext: "",
                    clarificationAnswers: "",
                    clarificationCycles: 0,
                    questionEpoch: 0,
                    shouldRunInline: true
                ),
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
            taskRuntimeState: nil,
            selectedConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
            draftText: "continue",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:],
            autoTodoRuntimeStateByMessage: [:]
        )
    }
}
