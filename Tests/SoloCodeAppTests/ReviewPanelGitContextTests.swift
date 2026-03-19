import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class ReviewPanelGitContextTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDownWithError() throws {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        try super.tearDownWithError()
    }

    func testRefreshGitContextLoadsBranchesAndCommitsFromRealRepository() async throws {
        let repo = try makeGitRepository(extraCommitCount: 0)
        try enableReviewCore()
        let store = makeStore(workspaceRoot: repo.path)

        await store.refreshGitContext()
        try await waitUntil("git context loaded") {
            store.gitContextStatus == .loaded && !store.gitCommitLog.isEmpty
        }

        XCTAssertFalse(store.currentGitBranch.isEmpty)
        XCTAssertTrue(store.gitBranches.contains(where: { $0.name == store.currentGitBranch || $0.isCurrent }))
        XCTAssertEqual(store.gitCommitLog.count, 1)
        XCTAssertFalse(store.isLoadingGit)
    }

    func testRefreshGitContextMarksNonRepositoryInsteadOfLeavingSilentEmptyState() async throws {
        let nonRepo = FileManager.default.temporaryDirectory.appendingPathComponent("review-panel-non-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        try enableReviewCore()
        let store = makeStore(workspaceRoot: nonRepo.path)

        await store.refreshGitContext()
        try await waitUntil("non-git failure surfaced") {
            if case .notRepository = store.gitContextStatus {
                return true
            }
            return false
        }

        if case .notRepository(let message) = store.gitContextStatus {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("repository git"))
        } else {
            XCTFail("Expected .notRepository, got \(store.gitContextStatus)")
        }
        XCTAssertTrue(store.gitBranches.isEmpty)
        XCTAssertTrue(store.gitRemoteBranches.isEmpty)
        XCTAssertTrue(store.gitCommitLog.isEmpty)
        XCTAssertEqual(store.currentGitBranch, "")
    }

    func testRefreshGitContextFailsExplicitlyWhenRustRuntimeIsDisabled() async throws {
        let repo = try makeGitRepository(extraCommitCount: 0)
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        let store = makeStore(workspaceRoot: repo.path)

        await store.refreshGitContext()
        try await waitUntil("runtime disabled surfaced") {
            if case .failed = store.gitContextStatus {
                return true
            }
            return false
        }

        if case .failed(let message) = store.gitContextStatus {
            XCTAssertTrue(message.localizedCaseInsensitiveContains("disabilitato"))
        } else {
            XCTFail("Expected .failed, got \(store.gitContextStatus)")
        }
        XCTAssertTrue(store.gitCommitLog.isEmpty)
        XCTAssertEqual(store.currentGitBranch, "")
    }

    func testLoadMoreCommitsExtendsHistoryBeyondInitialLimit() async throws {
        let repo = try makeGitRepository(extraCommitCount: 55)
        try enableReviewCore()
        let store = makeStore(workspaceRoot: repo.path)

        await store.refreshGitContext()
        try await waitUntil("initial git history loaded") {
            store.gitContextStatus == .loaded && store.gitCommitLog.count == 50
        }

        await store.loadMoreCommits(limit: 200)
        try await waitUntil("extended git history loaded") {
            store.gitContextStatus == .loaded && store.gitCommitLog.count == 56
        }

        XCTAssertEqual(store.gitCommitLog.count, 56)
        XCTAssertFalse(store.currentGitBranch.isEmpty)
    }

    private func makeStore(workspaceRoot: String) -> CodeReviewPanelStore {
        let workspaceStore = WorkspaceStore()
        workspaceStore.workspaces = [Workspace(name: "Repo", rootPath: workspaceRoot)]
        workspaceStore.activeWorkspaceId = workspaceStore.workspaces.first?.id
        return CodeReviewPanelStore(
            taskActivityStore: TaskActivityStore(),
            providerRegistry: ProviderRegistry(),
            executionController: nil,
            workspaceStore: workspaceStore,
            openFilesStore: OpenFilesStore(),
            conversationId: nil,
            providerFactoryConfigBuilder: { Self.makeProviderFactoryConfig() }
        )
    }

    private func makeGitRepository(extraCommitCount: Int) throws -> URL {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("review-panel-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo.path)
        try runGit(["config", "user.email", "review@example.com"], cwd: repo.path)
        try runGit(["config", "user.name", "Review Panel"], cwd: repo.path)

        let file = repo.appendingPathComponent("tracked.txt")
        try "0\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], cwd: repo.path)
        try runGit(["commit", "-m", "init"], cwd: repo.path)

        guard extraCommitCount > 0 else { return repo }
        for index in 1...extraCommitCount {
            try "\(index)\n".write(to: file, atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], cwd: repo.path)
            try runGit(["commit", "-m", "commit \(index)"], cwd: repo.path)
        }
        return repo
    }

    private func enableReviewCore() throws {
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }

    private func waitUntil(
        _ description: String,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(
                domain: "ReviewPanelGitContextTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed\nstdout: \(stdout)\nstderr: \(stderr)"]
            )
        }
    }

    private static func makeProviderFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(openaiApiKey: "", openaiModel: "gpt-4o-mini", anthropicApiKey: "", anthropicModel: "claude-3-5-haiku-latest", googleApiKey: "", googleModel: "gemini-2.0-flash", minimaxApiKey: "", minimaxModel: "MiniMax-M1", openrouterApiKey: "", openrouterModel: "openai/gpt-4o-mini", grokApiKey: "", grokModel: "grok-3-mini", codexPath: "", codexSandbox: "workspace-write", codexSessionFullAccess: false, codexAskForApproval: "never", codexModelOverride: "", codexReasoningEffort: "", codexFastMode: true, codexModelProvider: "", codexPreferResponsesWireAPI: false, planModeBackend: "openai-api", swarmOrchestrator: "openai-api", swarmWorkerBackend: "openai-api", swarmEnabledRoles: "", globalYolo: false, codeReviewPartitions: 2, codeReviewAnalysisOnly: false, codeReviewMaxRounds: 2, codeReviewAnalysisBackend: "openai-api", codeReviewExecutionBackend: "openai-api", claudePath: "", claudeModel: "claude-3-5-sonnet-latest", claudeAllowedTools: [], geminiCliPath: "", geminiModelOverride: "", unifiedToolRuntimeEnabled: true, agentsHardBlockEnabled: true, mcpEditEnforcementEnabled: true, webSearchProvider: "duckduckgo", braveSearchApiKey: "", tavilyApiKey: "", serperApiKey: "")
    }
}
