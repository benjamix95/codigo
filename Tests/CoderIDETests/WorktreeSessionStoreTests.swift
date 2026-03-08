import XCTest
@testable import CoderIDE

@MainActor
final class WorktreeSessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "worktree-session-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testUpsertAndReloadSessionFromUserDefaults() {
        let store = WorktreeSessionStore(userDefaults: defaults)
        let conversationId = UUID()
        let session = WorktreeSession(
            conversationId: conversationId,
            localRootPath: "/tmp/local",
            worktreePath: "/tmp/worktree",
            worktreeBranch: "solocode/test-1",
            baseBranch: "main",
            mergeTargetBranch: "main",
            autoMergeOnReturn: true,
            deleteBranchAfterMerge: false
        )
        store.upsert(session)

        let reloaded = WorktreeSessionStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.session(for: conversationId)?.worktreeBranch, "solocode/test-1")
        XCTAssertEqual(reloaded.session(for: conversationId)?.mergeTargetBranch, "main")
    }

    func testIsInWorktreeUsesPathPrefixMatching() {
        let store = WorktreeSessionStore(userDefaults: defaults)
        let conversationId = UUID()
        store.upsert(
            WorktreeSession(
                conversationId: conversationId,
                localRootPath: "/tmp/repo",
                worktreePath: "/tmp/repo-worktrees/solocode-abc",
                worktreeBranch: "solocode/abc",
                baseBranch: "main",
                mergeTargetBranch: "main",
                autoMergeOnReturn: true,
                deleteBranchAfterMerge: false
            )
        )

        XCTAssertTrue(
            store.isInWorktree(
                conversationId: conversationId,
                currentPath: "/tmp/repo-worktrees/solocode-abc/Sources"
            )
        )
        XCTAssertFalse(
            store.isInWorktree(conversationId: conversationId, currentPath: "/tmp/repo")
        )
        XCTAssertTrue(
            store.isInLocal(conversationId: conversationId, currentPath: "/tmp/repo")
        )
    }

    func testIsInWorktreeRequiresDirectoryBoundaryMatch() {
        let store = WorktreeSessionStore(userDefaults: defaults)
        let conversationId = UUID()
        store.upsert(
            WorktreeSession(
                conversationId: conversationId,
                localRootPath: "/tmp/repo",
                worktreePath: "/tmp/repo-worktrees/solocode-abc",
                worktreeBranch: "solocode/abc",
                baseBranch: "main",
                mergeTargetBranch: "main",
                autoMergeOnReturn: true,
                deleteBranchAfterMerge: false
            )
        )

        XCTAssertFalse(
            store.isInWorktree(
                conversationId: conversationId,
                currentPath: "/tmp/repo-worktrees/solocode-abc-extra"
            )
        )
        XCTAssertFalse(
            store.isInLocal(
                conversationId: conversationId,
                currentPath: "/tmp/repository"
            )
        )
    }
}
