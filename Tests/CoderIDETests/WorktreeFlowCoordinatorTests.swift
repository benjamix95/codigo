import XCTest
@testable import CoderIDE

@MainActor
final class WorktreeFlowCoordinatorTests: XCTestCase {
    private var repoURL: URL!
    private var chatDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: repoURL)

        suiteName = "worktree-flow-chat-\(UUID().uuidString)"
        chatDefaults = UserDefaults(suiteName: suiteName)
        chatDefaults.removePersistentDomain(forName: suiteName)
        clearContextPersistence()
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        if let suiteName {
            chatDefaults?.removePersistentDomain(forName: suiteName)
        }
        clearContextPersistence()
        repoURL = nil
        chatDefaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testLoadSheetBootstrapReturnsSuggestedDefaults() async throws {
        let coordinator = WorktreeFlowCoordinator()
        let bootstrap = try await coordinator.loadSheetBootstrap(localRootPath: repoURL.path)

        XCTAssertEqual(bootstrap.localRootPath, repoURL.path)
        XCTAssertEqual(bootstrap.currentBranch, bootstrap.suggestedBaseBranch)
        XCTAssertEqual(bootstrap.suggestedMergeTargetBranch, bootstrap.currentBranch)
        XCTAssertTrue(bootstrap.suggestedWorktreeBranch.hasPrefix("solocode/"))
        XCTAssertTrue(bootstrap.suggestedWorktreeBranch.contains(sanitizeWorktreeBranchComponent(bootstrap.currentBranch)))
        XCTAssertTrue(bootstrap.localBranches.contains(where: { $0.isCurrent }))
    }

    func testCreateAndSwitchRollsBackWorktreeIfRouterFails() async throws {
        let chatStore = ChatStore(userDefaults: chatDefaults)
        let conversationId = chatStore.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        let projectContextStore = ProjectContextStore()
        let workspaceStore = WorkspaceStore()
        let gitService = GitService()
        let root = try gitService.resolveGitRoot(from: repoURL.path)
        let currentBranch = try gitService.currentBranch(gitRoot: root)
        let branch = "solocode/fail-\(UUID().uuidString.prefix(6))"
        let worktreePath = repoURL
            .deletingLastPathComponent()
            .appendingPathComponent("repo-worktrees")
            .appendingPathComponent("fail-router")
            .path
        let coordinator = WorktreeFlowCoordinator(
            gitService: gitService,
            router: FailingWorktreeRouter()
        )
        let input = try coordinator.validateCreateInput(
            conversationId: conversationId,
            localRootPath: root,
            worktreeBranch: branch,
            baseBranch: currentBranch,
            mergeTargetBranch: currentBranch,
            worktreePath: worktreePath,
            autoMergeOnReturn: true,
            deleteBranchAfterMerge: false
        )

        var persistedSessions: [WorktreeSession] = []

        do {
            _ = try await coordinator.createAndSwitch(
                input: input,
                chatStore: chatStore,
                projectContextStore: projectContextStore,
                workspaceStore: workspaceStore
            ) { session in
                persistedSessions.append(session)
            }
            XCTFail("Expected createAndSwitch to fail when router throws.")
        } catch let error as WorktreeFlowError {
            guard case .switchFailedAfterCreate(_, let rollbackPerformed) = error else {
                return XCTFail("Unexpected worktree flow error: \(error)")
            }
            XCTAssertTrue(rollbackPerformed)
        }

        XCTAssertTrue(persistedSessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreePath))
        XCTAssertFalse(try gitService.branchExists(name: branch, gitRoot: root))
    }

    private func clearContextPersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.projectContexts")
        defaults.removeObject(forKey: "CoderIDE.activeContextId")
        defaults.removeObject(forKey: "CoderIDE.lastActiveConversationByContext")
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
    }

    private func initializeGitRepository(at url: URL) throws {
        try runGit(["init"], cwd: url.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: url.path)
        try runGit(["config", "user.name", "Git Test"], cwd: url.path)
        try "hello".write(
            to: url.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], cwd: url.path)
        try runGit(["commit", "-m", "init"], cwd: url.path)
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stdout = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw NSError(
                domain: "WorktreeFlowCoordinatorTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "git failed\nstdout: \(stdout)\nstderr: \(stderr)"
                ]
            )
        }
    }
}

@MainActor
private struct FailingWorktreeRouter: WorktreeConversationRouting {
    func switchConversation(
        conversationId: UUID?,
        toProjectPath projectPath: String,
        chatStore: ChatStore,
        projectContextStore: ProjectContextStore,
        workspaceStore: WorkspaceStore
    ) throws {
        throw GitServiceError.commandFailed("Router failure")
    }
}
