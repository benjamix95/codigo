import XCTest
@testable import CoderIDE
import CoderEngine

@MainActor
final class CodeReviewPanelSessionScopingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReviewPanelChatSessionStore.shared.clearAll()
    }

    func testScopedReviewActivitiesForSessionFiltersMismatchedSession() {
        let activities = [
            TaskActivity(type: "review-worker-plan", title: "a", payload: ["session_id": "s1"]),
            TaskActivity(type: "review-worker-plan", title: "b", payload: ["session_id": "s2"]),
            TaskActivity(type: "review-worker-plan", title: "c", payload: [:]),
        ]

        let scoped = scopedReviewActivitiesForSession(activities, sessionId: "s1")
        XCTAssertEqual(scoped.map(\.title), ["a"])
    }

    func testReviewCardBelongsToSessionUsesRecentEvents() {
        let card = SwarmLiveCardState(
            swarmId: "worker-1",
            recentEvents: [
                TaskActivity(type: "agent", title: "s1", payload: ["session_id": "s1"]),
                TaskActivity(type: "agent", title: "s2", payload: ["session_id": "s2"]),
            ]
        )

        XCTAssertTrue(reviewCardBelongsToSession(card, sessionId: "s1"))
        XCTAssertFalse(reviewCardBelongsToSession(card, sessionId: "missing"))
    }

    func testCodeReviewSnapshotRejectsExplicitSessionFromDifferentConversation() {
        let store = TaskActivityStore()
        let conversationA = UUID()
        let conversationB = UUID()
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-a",
            conversationId: conversationA,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: nil,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        store.ingestCodeReviewSnapshot(snapshot, conversationId: conversationA)

        let resolved = store.codeReviewSnapshot(
            sessionId: "session-a",
            conversationId: conversationB
        )

        XCTAssertNil(resolved)
    }

    func testPanelStoreScopesSnapshotsToConversation() {
        let taskStore = TaskActivityStore()
        let conversationA = UUID()
        let conversationB = UUID()
        taskStore.ingestCodeReviewSnapshot(
            makeSnapshot(sessionId: "session-a", conversationId: conversationA),
            conversationId: conversationA
        )
        taskStore.ingestCodeReviewSnapshot(
            makeSnapshot(sessionId: "session-b", conversationId: conversationB),
            conversationId: conversationB
        )

        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationA
        )

        XCTAssertEqual(store.availableSnapshots.map(\.sessionId), ["session-a"])
        XCTAssertEqual(store.selectedSessionId, "session-a")
    }

    func testPanelStoreRestoresCachedChatSessionState() {
        let conversationId = UUID()
        let sessionKey = CodeReviewPanelStore.chatSessionKey(conversationId: conversationId)
        ReviewPanelChatSessionStore.shared.replaceState(
            ReviewPanelChatSessionState(
                messages: [
                    ReviewPanelMessage(role: .user, content: "Run review"),
                    ReviewPanelMessage(role: .assistant, content: "Streaming...", isStreaming: true),
                ],
                isProcessing: true,
                startedAt: Date(timeIntervalSinceReferenceDate: 42)
            ),
            for: sessionKey
        )

        let store = makePanelStore(
            taskActivityStore: TaskActivityStore(),
            conversationId: conversationId
        )

        XCTAssertEqual(store.chatMessages.count, 2)
        XCTAssertTrue(store.isChatProcessing)
        XCTAssertEqual(store.chatMessages.last?.content, "Streaming...")
        XCTAssertTrue(store.chatMessages.last?.isStreaming == true)
    }

    func testPanelFallbackApplyFixOnlyMutatesRequestedFinding() async throws {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let snapshot = makeSnapshot(
            sessionId: "session-fallback",
            conversationId: conversationId,
            findings: [
                CodeReviewFinding(
                    id: "f-1",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/A.swift",
                    message: "First finding"
                ),
                CodeReviewFinding(
                    id: "f-2",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/B.swift",
                    message: "Second finding"
                ),
            ]
        )
        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationId
        )

        await store.applyFix(sessionId: "session-fallback", findingId: "f-1")

        let updated = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: "session-fallback",
                conversationId: conversationId
            )
        )
        XCTAssertEqual(updated.findings.first(where: { $0.id == "f-1" })?.status, .fixApplied)
        XCTAssertEqual(updated.findings.first(where: { $0.id == "f-2" })?.status, .open)
    }

    private func makePanelStore(
        taskActivityStore: TaskActivityStore,
        conversationId: UUID?
    ) -> CodeReviewPanelStore {
        CodeReviewPanelStore(
            taskActivityStore: taskActivityStore,
            providerRegistry: ProviderRegistry(),
            executionController: nil,
            workspaceStore: WorkspaceStore(),
            openFilesStore: OpenFilesStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
    }

    private func makeSnapshot(
        sessionId: String,
        conversationId: UUID,
        findings: [CodeReviewFinding] = []
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: findings,
            events: [],
            config: .default,
            scope: nil,
            workspacePath: nil,
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
    }

    private static func makeProviderFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: "",
            openaiModel: "gpt-4o-mini",
            anthropicApiKey: "",
            anthropicModel: "claude-3-5-haiku-latest",
            googleApiKey: "",
            googleModel: "gemini-2.0-flash",
            minimaxApiKey: "",
            minimaxModel: "MiniMax-M1",
            openrouterApiKey: "",
            openrouterModel: "openai/gpt-4o-mini",
            grokApiKey: "",
            grokModel: "grok-3-mini",
            codexPath: "",
            codexSandbox: "workspace-write",
            codexSessionFullAccess: false,
            codexAskForApproval: "never",
            codexModelOverride: "",
            codexReasoningEffort: "",
            codexFastMode: true,
            codexModelProvider: "",
            codexPreferResponsesWireAPI: false,
            planModeBackend: "openai-api",
            swarmOrchestrator: "openai-api",
            swarmWorkerBackend: "openai-api",
            swarmEnabledRoles: "",
            globalYolo: false,
            codeReviewPartitions: 2,
            codeReviewAnalysisOnly: false,
            codeReviewMaxRounds: 2,
            codeReviewAnalysisBackend: "openai-api",
            codeReviewExecutionBackend: "openai-api",
            claudePath: "",
            claudeModel: "claude-3-5-sonnet-latest",
            claudeAllowedTools: [],
            geminiCliPath: "",
            geminiModelOverride: "",
            unifiedToolRuntimeEnabled: true,
            agentsHardBlockEnabled: true,
            mcpEditEnforcementEnabled: true,
            webSearchProvider: "duckduckgo",
            braveSearchApiKey: "",
            tavilyApiKey: "",
            serperApiKey: ""
        )
    }
}
