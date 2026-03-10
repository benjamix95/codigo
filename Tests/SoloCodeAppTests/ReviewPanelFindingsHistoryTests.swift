import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelFindingsHistoryTests: XCTestCase {
    func testResumeQueuePrioritizesOpenHistoricalFindings() {
        let store = makeStore()
        store.historyRecords = [
            HistoricalFindingRecord(
                findingId: "resolved-1",
                sessionId: "session-a",
                workspaceId: "/tmp/workspace",
                domain: .bug,
                severity: .medium,
                title: "Resolved finding",
                summary: "Already closed",
                status: .fixedVerified,
                filePath: "Sources/Resolved.swift",
                lineStart: 10,
                sourceOrigin: "bugHunter",
                closedReason: "fixed",
                patchId: "patch-resolved",
                patchApplyStatus: .applied,
                revalidationReportId: "revalidation-resolved",
                revalidationVerdict: .fixedVerified,
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 200),
                resolvedAt: Date(timeIntervalSince1970: 200),
                resumeEligible: false,
                timeline: []
            ),
            HistoricalFindingRecord(
                findingId: "open-1",
                sessionId: "session-b",
                workspaceId: "/tmp/workspace",
                domain: .security,
                severity: .high,
                title: "Resume me",
                summary: "Patch ready but not closed",
                status: .patchPrepared,
                filePath: "Sources/Open.swift",
                lineStart: 20,
                sourceOrigin: "securityAuditor",
                closedReason: nil,
                patchId: "patch-open",
                patchApplyStatus: .notApplied,
                revalidationReportId: nil,
                revalidationVerdict: nil,
                createdAt: Date(timeIntervalSince1970: 150),
                updatedAt: Date(timeIntervalSince1970: 250),
                resolvedAt: nil,
                resumeEligible: true,
                timeline: []
            ),
        ]

        XCTAssertEqual(store.historicalResumeQueue.map(\.findingId), ["open-1"])
        XCTAssertEqual(store.filteredHistoricalFindings.map(\.findingId), ["open-1"])

        store.historyStatusFilter = .resolved
        XCTAssertEqual(store.filteredHistoricalFindings.map(\.findingId), ["resolved-1"])
    }

    func testHistoricalResumePromptIncludesPersistedLifecycleContext() {
        let store = makeStore()
        let record = HistoricalFindingRecord(
            findingId: "finding-1",
            sessionId: "session-1",
            workspaceId: "/tmp/workspace",
            domain: .security,
            severity: .high,
            title: "Missing authorization guard",
            summary: "Verified on direct path",
            status: .patchPrepared,
            filePath: "Sources/Auth.swift",
            lineStart: 42,
            sourceOrigin: "securityAuditor",
            closedReason: nil,
            patchId: "patch-1",
            patchApplyStatus: .notApplied,
            revalidationReportId: nil,
            revalidationVerdict: nil,
            createdAt: Date(),
            updatedAt: Date(),
            resolvedAt: nil,
            resumeEligible: true,
            timeline: []
        )

        let prompt = store.historicalResumePrompt(for: record)

        XCTAssertTrue(prompt.contains("finding-1"))
        XCTAssertTrue(prompt.contains("Sources/Auth.swift:42"))
        XCTAssertTrue(prompt.contains("securityAuditor"))
        XCTAssertTrue(prompt.contains("patch_prepared"))
        XCTAssertTrue(prompt.contains("not_applied"))
    }

    func testRefreshHistoricalFindingsReadsPersistedWorkspaceHistory() async throws {
        resetPersistenceEnvironment()
        enablePersistenceForTests()
        defer { resetPersistenceEnvironment() }

        let stableDate = Date(timeIntervalSince1970: 1_700_000_000)
        let persistenceStore = PostgresPersistenceStore(postgresService: ManagedPostgresService())
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "history-session",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "history-1",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/History.swift",
                    lineNumber: 18,
                    message: "Retry may emit terminal event twice",
                    status: .open,
                    verificationReport: "Verified with persisted history",
                    verifiedAt: stableDate,
                    createdAt: stableDate
                )
            ],
            patches: [],
            events: [
                .findingAdded(findingId: "history-1", severity: "warning", filePath: "Sources/History.swift")
            ],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/History.swift"]),
            workspacePath: "/tmp/history-workspace",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: stableDate,
            completedAt: stableDate.addingTimeInterval(30),
            analysisCompletedAt: stableDate.addingTimeInterval(5),
            lastError: nil,
            currentJobId: "job-history",
            lastTestStatus: .passed,
            lastUpdatedAt: stableDate.addingTimeInterval(30)
        )
        try persistenceStore.persistCodeReviewSnapshot(snapshot)

        let store = makeStore(workspacePath: "/tmp/history-workspace")
        await store.refreshHistoricalFindings()

        XCTAssertFalse(store.isHistoryLoading)
        XCTAssertNil(store.historyLoadError)
        XCTAssertEqual(store.historyRecords.map(\.findingId), ["history-1"])
        XCTAssertEqual(store.historyRecords.first?.filePath, "Sources/History.swift")
        XCTAssertEqual(store.historyRecords.first?.lineStart, 18)
        XCTAssertEqual(store.historyRecords.first?.status, .verified)
    }

    private func makeStore(
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
            taskActivityStore: TaskActivityStore(),
            providerRegistry: registry,
            executionController: nil,
            workspaceStore: workspaceStore,
            openFilesStore: OpenFilesStore(),
            todoStore: TodoStore(),
            conversationId: UUID(),
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

    private func enablePersistenceForTests() {
        unsetenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE")
        setenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS", "1", 1)
    }

    private func resetPersistenceEnvironment() {
        unsetenv("SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS")
        setenv("SOLOCODE_DISABLE_POSTGRES_PERSISTENCE", "1", 1)
        try? ManagedPostgresService.shared.shutdownIfRunning()
        try? FileManager.default.removeItem(at: ManagedPostgresConfiguration.default.rootDirectory)
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.planStateFilePath)
    }
}
