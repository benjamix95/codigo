import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelFindingsHistoryRustFallbackTests: XCTestCase {
    func testFallbackHistoricalFindingsUsesRustDerivedSnapshotRecords() {
        let taskStore = TaskActivityStore()
        let conversationId = UUID()
        let store = makeStore(
            taskActivityStore: taskStore,
            conversationId: conversationId,
            workspacePath: "/tmp/history-fallback-rust"
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "history-fallback-session",
            conversationId: conversationId,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "history-fallback-1",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/Fallback.swift",
                    lineNumber: 33,
                    message: "Fallback history should be rust derived",
                    status: .patchApplied,
                    verificationReport: "verified",
                    verifiedAt: Date(timeIntervalSince1970: 50),
                    createdAt: Date(timeIntervalSince1970: 40)
                )
            ],
            patches: [
                ReviewPatchArtifact(
                    id: "patch-fallback-1",
                    findingId: "history-fallback-1",
                    patchText: "guard let session else { return }",
                    diffPreview: "diff --git a/Sources/Fallback.swift b/Sources/Fallback.swift",
                    touchedFiles: ["Sources/Fallback.swift"],
                    status: .applied,
                    verifyStatus: .verified,
                    validationStatus: .passed,
                    updatedAt: Date(timeIntervalSince1970: 60)
                )
            ],
            events: [
                .findingAdded(
                    findingId: "history-fallback-1",
                    severity: "warning",
                    filePath: "Sources/Fallback.swift"
                )
            ],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/Fallback.swift"]),
            workspacePath: "/tmp/history-fallback-rust",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 60),
            analysisCompletedAt: Date(timeIntervalSince1970: 20),
            lastError: nil,
            currentJobId: "job-fallback",
            lastTestStatus: .passed,
            lastUpdatedAt: Date(timeIntervalSince1970: 60)
        )
        taskStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)

        let records = store.fallbackHistoricalFindings()

        XCTAssertEqual(records.map(\.findingId), ["history-fallback-1"])
        XCTAssertEqual(records.first?.status, .fixedVerified)
        XCTAssertEqual(records.first?.patchApplyStatus, .applied)
        XCTAssertEqual(records.first?.filePath, "Sources/Fallback.swift")
    }

    private func makeStore(
        taskActivityStore: TaskActivityStore,
        conversationId: UUID,
        workspacePath: String
    ) -> CodeReviewPanelStore {
        let registry = ProviderRegistry()
        registry.selectedProviderId = "openai-api"
        let workspaceStore = WorkspaceStore()
        let workspace = Workspace(name: "History", rootPath: workspacePath)
        workspaceStore.workspaces = [workspace]
        workspaceStore.activeWorkspaceId = workspace.id
        return CodeReviewPanelStore(
            taskActivityStore: taskActivityStore,
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
                    codeReviewPartitions: 4,
                    codeReviewAnalysisOnly: false,
                    codeReviewMaxRounds: 3,
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
                    serperApiKey: "",
                )
            }
        )
    }
}
