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
        _ = ReviewPanelChatSessionStore.shared.createThread(for: sessionKey, title: "Cached")
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
        XCTAssertEqual(store.chatThreads.count, 1)
    }

    func testDeleteSessionRemovesSnapshotAndClearsSelection() async {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let snapshot = makeSnapshot(
            sessionId: "session-delete",
            conversationId: conversationId
        )
        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationId
        )
        store.setSelectedSession("session-delete")

        await store.deleteSession("session-delete")

        XCTAssertTrue(store.availableSnapshots.isEmpty)
        XCTAssertNil(store.selectedSessionId)
        XCTAssertNil(
            taskStore.codeReviewSnapshot(
                sessionId: "session-delete",
                conversationId: conversationId
            )
        )
    }

    func testPanelApplyFixFailsClosedWithoutWorkspaceAndDoesNotTouchOtherFindings() async throws {
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
        XCTAssertEqual(updated.findings.first(where: { $0.id == "f-1" })?.status, .patchFailed)
        XCTAssertEqual(updated.findings.first(where: { $0.id == "f-2" })?.status, .open)
    }

    func testPanelDismissFallbackUsesRustMutationAndMarksWontFix() async throws {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let snapshot = makeSnapshot(
            sessionId: "session-dismiss",
            conversationId: conversationId,
            findings: [
                CodeReviewFinding(
                    id: "f-1",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/A.swift",
                    message: "Dismiss me"
                )
            ]
        )
        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationId
        )

        await store.dismissFinding(
            sessionId: "session-dismiss",
            findingId: "f-1",
            reason: "wont_fix"
        )

        let updated = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: "session-dismiss",
                conversationId: conversationId
            )
        )
        XCTAssertEqual(updated.findings.first?.status, .wontFix)
        XCTAssertEqual(updated.events.last?.type, .findingDismissed)
        XCTAssertEqual(updated.events.last?.metadata["finding_id"], "f-1")
    }

    func testPanelModeSelectionAllowsMultiSelectAndSecondTapTurnsModeOff() {
        let store = makePanelStore(
            taskActivityStore: TaskActivityStore(),
            conversationId: nil
        )

        store.toggleModeSelection(.securityAudit)
        store.toggleModeSelection(.bugFinder)

        XCTAssertTrue(store.hasSelectedMode(.standard))
        XCTAssertTrue(store.hasSelectedMode(.securityAudit))
        XCTAssertTrue(store.hasSelectedMode(.bugFinder))

        store.toggleModeSelection(.securityAudit)

        XCTAssertFalse(store.hasSelectedMode(.securityAudit))
        XCTAssertTrue(store.hasSelectedMode(.bugFinder))
    }

    func testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates() async throws {
        let taskStore = TaskActivityStore()
        let conversationId = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let sessionId = "review-session-chat"
        taskStore.ingestCodeReviewSnapshot(
            makeSnapshot(sessionId: sessionId, conversationId: conversationId),
            conversationId: conversationId
        )

        let store = makePanelStore(
            taskActivityStore: taskStore,
            conversationId: conversationId
        )
        store.setSelectedSession(sessionId)

        let firstMessageId = UUID()
        store.appendChatMessage(
            ReviewPanelMessage(
                id: firstMessageId,
                role: .assistant,
                kind: .reviewRun,
                content: """
                ## Findings
                - Ho trovato un bug reale.

                ```review_findings
                {
                  "findings": [
                    {
                      "severity": "warning",
                      "category": "correctness",
                      "file": "Sources/App/Main.swift",
                      "line": 42,
                      "message": "Missing guard before dereferencing the session",
                      "suggested_fix": "Add a guard for the active session before reading the snapshot.",
                      "confidence": 0.91
                    }
                  ]
                }
                ```
                """
            )
        )

        await store.syncStructuredFindingsFromChatResponse(messageId: firstMessageId)

        let firstSnapshot = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
            )
        )
        XCTAssertEqual(firstSnapshot.findings.count, 1)
        XCTAssertEqual(firstSnapshot.candidates.count, 0)
        XCTAssertEqual(firstSnapshot.findings.first?.filePath, "Sources/App/Main.swift")
        XCTAssertEqual(firstSnapshot.findings.first?.lineNumber, 42)
        XCTAssertEqual(
            firstSnapshot.findings.first?.suggestedFix,
            "Add a guard for the active session before reading the snapshot."
        )
        XCTAssertEqual(firstSnapshot.events.count, 1)
        XCTAssertEqual(firstSnapshot.events.first?.type, .findingAdded)
        XCTAssertEqual(firstSnapshot.events.first?.metadata["file_path"], "Sources/App/Main.swift")
        XCTAssertFalse(
            store.chatMessages.first(where: { $0.id == firstMessageId })?.content.contains("```review_findings") ?? true
        )

        let duplicateMessageId = UUID()
        store.appendChatMessage(
            ReviewPanelMessage(
                id: duplicateMessageId,
                role: .assistant,
                kind: .reviewRun,
                content: """
                ## Findings
                - Ripeto lo stesso finding.

                ```review_findings
                {
                  "findings": [
                    {
                      "severity": "warning",
                      "category": "correctness",
                      "file": "Sources/App/Main.swift",
                      "line": 42,
                      "message": "Missing guard before dereferencing the session",
                      "suggested_fix": "Add a guard for the active session before reading the snapshot.",
                      "confidence": 0.91
                    }
                  ]
                }
                ```
                """
            )
        )

        await store.syncStructuredFindingsFromChatResponse(messageId: duplicateMessageId)

        let deduplicatedSnapshot = try XCTUnwrap(
            taskStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: conversationId
            )
        )
        XCTAssertEqual(deduplicatedSnapshot.findings.count, 1)
        XCTAssertEqual(
            deduplicatedSnapshot.events.filter { $0.type == .findingAdded }.count,
            1
        )
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
