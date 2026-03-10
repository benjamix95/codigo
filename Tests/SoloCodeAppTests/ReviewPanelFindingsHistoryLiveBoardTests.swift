import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelFindingsHistoryLiveBoardTests: XCTestCase {
    func testCurrentHistoricalLiveRunStateBuildsRealtimeFileBoardFromWorkerPlans() {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = makeStore(
            taskActivityStore: taskStore,
            conversationId: conversationId,
            workspacePath: "/tmp/live-workspace"
        )
        let sessionId = "session-live"
        taskStore.ingestCodeReviewSnapshot(
            CodeReviewSessionSnapshot(
                sessionId: sessionId,
                conversationId: conversationId,
                phase: .analyzing,
                stage: .analysis,
                findings: [],
                events: [],
                config: .default,
                scope: ReviewSessionScope(type: .workspace, files: ["Sources/A.swift", "Sources/B.swift"]),
                workspacePath: "/tmp/live-workspace",
                currentRound: 0,
                activeWorkerCount: 2,
                startedAt: Date(),
                completedAt: nil,
                analysisCompletedAt: nil,
                lastError: nil,
                currentJobId: "job-live",
                lastTestStatus: nil,
                lastUpdatedAt: Date()
            ),
            conversationId: conversationId
        )
        taskStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)

        taskStore.addActivity(
            TaskActivity(
                type: "review-worker-plan",
                title: "worker-1",
                detail: "planned",
                payload: [
                    "session_id": sessionId,
                    "conversation_id": conversationId.uuidString.lowercased(),
                    "worker_id": "worker-1",
                    "description": "Analyze retry paths",
                    "severity": "warning",
                    "fileCount": "2",
                    "files_raw": "Sources/A.swift\nSources/B.swift",
                    "files": "Sources/A.swift, Sources/B.swift",
                ],
                phase: .executing,
                isRunning: true,
                groupId: "review-worker-1"
            )
        )
        taskStore.addActivity(
            TaskActivity(
                type: "review-worker-plan",
                title: "worker-2",
                detail: "planned",
                payload: [
                    "session_id": sessionId,
                    "conversation_id": conversationId.uuidString.lowercased(),
                    "worker_id": "worker-2",
                    "description": "Analyze auth guards",
                    "severity": "critical",
                    "fileCount": "1",
                    "files_raw": "Sources/B.swift",
                    "files": "Sources/B.swift",
                ],
                phase: .executing,
                isRunning: true,
                groupId: "review-worker-2"
            )
        )
        store.panelSessionId = sessionId

        let live = store.currentHistoricalLiveRunState

        XCTAssertEqual(live?.title, "Live Review Board")
        XCTAssertEqual(live?.workers.count, 2)
        XCTAssertEqual(live?.files.map(\.path), ["Sources/B.swift", "Sources/A.swift"])
        XCTAssertEqual(live?.files.first?.workerIDs, ["worker-1", "worker-2"])
        XCTAssertEqual(live?.files.first?.severity, .critical)
        XCTAssertEqual(live?.isRunning, true)
    }

    func testCurrentHistoricalLiveRunStateRemainsVisibleAsCompletedSummary() {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = makeStore(
            taskActivityStore: taskStore,
            conversationId: conversationId,
            workspacePath: "/tmp/completed-workspace"
        )
        let sessionId = "session-completed"
        taskStore.ingestCodeReviewSnapshot(
            CodeReviewSessionSnapshot(
                sessionId: sessionId,
                conversationId: conversationId,
                phase: .completed,
                stage: .completed,
                findings: [],
                events: [],
                config: .default,
                scope: ReviewSessionScope(type: .workspace, files: ["Sources/A.swift"]),
                workspacePath: "/tmp/completed-workspace",
                currentRound: 1,
                activeWorkerCount: 0,
                startedAt: Date(timeIntervalSince1970: 100),
                completedAt: Date(timeIntervalSince1970: 200),
                analysisCompletedAt: Date(timeIntervalSince1970: 150),
                lastError: nil,
                currentJobId: "job-complete",
                lastTestStatus: .passed,
                lastUpdatedAt: Date(timeIntervalSince1970: 200)
            ),
            conversationId: conversationId
        )
        taskStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)
        store.panelSessionId = sessionId

        let live = store.currentHistoricalLiveRunState

        XCTAssertEqual(live?.title, "Completed Run Summary")
        XCTAssertEqual(live?.isRunning, false)
        XCTAssertNotNil(live?.pipeline)
    }

    private func makeStore(
        taskActivityStore: TaskActivityStore? = nil,
        conversationId: UUID = UUID(),
        workspacePath: String? = nil
    ) -> CodeReviewPanelStore {
        let registry = ProviderRegistry()
        registry.selectedProviderId = "openai-api"
        let workspaceStore = WorkspaceStore()
        if let workspacePath {
            let workspace = Workspace(name: "History", rootPath: workspacePath)
            workspaceStore.workspaces = [workspace]
            workspaceStore.activeWorkspaceId = workspace.id
        } else {
            workspaceStore.workspaces = []
            workspaceStore.activeWorkspaceId = nil
        }
        return CodeReviewPanelStore(
            taskActivityStore: taskActivityStore ?? TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: workspaceStore,
            openFilesStore: OpenFilesStore(),
            todoStore: TodoStore(),
            conversationId: conversationId,
            providerFactoryConfigBuilder: {
                ProviderFactoryConfig(
                    openaiApiKey: "",
                    openaiModel: "gpt-4o-mini",
                    anthropicApiKey: "",
                    anthropicModel: "claude-sonnet-4-6",
                    googleApiKey: "",
                    googleModel: "gemini-2.5-pro",
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
                    claudeModel: "claude-sonnet-4-6",
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
        )
    }
}
