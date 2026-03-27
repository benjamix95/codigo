import XCTest
@testable import CoderIDE

final class GitServiceTests: XCTestCase {
    private var repoURL: URL?
    private let git = GitService()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("git-service-\(UUID().uuidString)")
        repoURL = repo
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo.path)
        try runGit(["config", "user.name", "Git Test"], cwd: repo.path)
        try "hello".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: repo.path)
        try runGit(["commit", "-m", "init"], cwd: repo.path)
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try super.tearDownWithError()
    }

    func testBranchAndStatusAndCommit() async throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let current = try git.currentBranch(gitRoot: root)
        XCTAssertFalse(current.isEmpty)
        let branches = try git.listLocalBranches(gitRoot: root)
        XCTAssertTrue(branches.contains(where: { $0.isCurrent }))

        try "change".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let status = try git.status(gitRoot: root)
        XCTAssertGreaterThan(status.changedFiles, 0)
        try runGit(["add", "a.txt"], cwd: repo.path)

        do {
            _ = try await git.commit(
                gitRoot: root,
                message: "chore: update file",
                includeUnstaged: false
            )
            XCTFail("Expected validation failure in temporary non-SoloCode repo")
        } catch let error as GitServiceError {
            guard case .validationFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testPushWithoutRemoteFails() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        XCTAssertThrowsError(try git.push(gitRoot: root, branch: try git.currentBranch(gitRoot: root)))
    }

    func testFileDiffHeadIncludesStagedAndUnstagedChanges() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let fileURL = repo.appendingPathComponent("a.txt")

        try "hello\nstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "a.txt"], cwd: repo.path)
        try "hello\nstaged\nunstaged\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let headDiff = try git.fileDiff(gitRoot: root, path: "a.txt", baseline: .head)
        let worktreeDiff = try git.fileDiff(gitRoot: root, path: "a.txt", baseline: .worktree)

        let headAdded = countAddedLines(in: headDiff)
        let worktreeAdded = countAddedLines(in: worktreeDiff)

        XCTAssertGreaterThanOrEqual(headAdded, 2)
        XCTAssertLessThan(worktreeAdded, headAdded)
    }

    func testChangedFilesIncludesBatchedStatsForStagedUnstagedAndUntrackedFiles() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)

        let unstagedURL = repo.appendingPathComponent("a.txt")
        try "hello\nupdated\n".write(to: unstagedURL, atomically: true, encoding: .utf8)

        let stagedURL = repo.appendingPathComponent("staged.txt")
        try "staged line\n".write(to: stagedURL, atomically: true, encoding: .utf8)
        try runGit(["add", "staged.txt"], cwd: repo.path)

        let untrackedURL = repo.appendingPathComponent("untracked.txt")
        try "one\ntwo\n".write(to: untrackedURL, atomically: true, encoding: .utf8)

        let changedFiles = try git.changedFiles(gitRoot: root)
        let byPath = Dictionary(uniqueKeysWithValues: changedFiles.map { ($0.path, $0) })

        let unstaged = try XCTUnwrap(byPath["a.txt"])
        XCTAssertEqual(unstaged.status, "M")
        XCTAssertFalse(unstaged.isStaged)
        XCTAssertEqual(unstaged.added, 1)
        XCTAssertEqual(unstaged.removed, 0)

        let staged = try XCTUnwrap(byPath["staged.txt"])
        XCTAssertEqual(staged.status, "A")
        XCTAssertTrue(staged.isStaged)
        XCTAssertEqual(staged.added, 1)
        XCTAssertEqual(staged.removed, 0)

        let untracked = try XCTUnwrap(byPath["untracked.txt"])
        XCTAssertEqual(untracked.status, "??")
        XCTAssertFalse(untracked.isStaged)
        XCTAssertEqual(untracked.added, 2)
        XCTAssertEqual(untracked.removed, 0)
    }

    func testCreateAndRemoveWorktreeLifecycle() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let baseBranch = try git.currentBranch(gitRoot: root)
        let branch = "solocode/worktree-\(UUID().uuidString.prefix(6))"
        let worktreePath = repo
            .deletingLastPathComponent()
            .appendingPathComponent("repo-worktrees")
            .appendingPathComponent(branch.replacingOccurrences(of: "/", with: "-"))

        try git.createWorktree(
            request: GitWorktreeCreateRequest(
                gitRoot: root,
                branchName: branch,
                fromBranch: baseBranch,
                worktreePath: worktreePath.path
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreePath.path))
        XCTAssertTrue(
            try git.listLocalBranches(gitRoot: root).contains(where: { $0.name == branch })
        )

        try git.removeWorktree(gitRoot: root, worktreePath: worktreePath.path, force: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreePath.path))

        try git.deleteMergedBranch(name: branch, gitRoot: root)
        XCTAssertFalse(
            try git.listLocalBranches(gitRoot: root).contains(where: { $0.name == branch })
        )
    }

    func testStartNoCommitMergeDetectsConflictsAndAbortRestoresState() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let baseBranch = try git.currentBranch(gitRoot: root)
        let sourceBranch = "solocode/conflict-\(UUID().uuidString.prefix(6))"
        let fileURL = repo.appendingPathComponent("a.txt")

        try runGit(["checkout", "-b", sourceBranch], cwd: repo.path)
        try "from-source\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "a.txt"], cwd: repo.path)
        try runGit(["commit", "-m", "source"], cwd: repo.path)

        try runGit(["checkout", baseBranch], cwd: repo.path)
        try "from-target\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try runGit(["add", "a.txt"], cwd: repo.path)
        try runGit(["commit", "-m", "target"], cwd: repo.path)

        let mergeResult = try git.startNoCommitMerge(
            sourceBranch: sourceBranch,
            intoTarget: baseBranch,
            gitRoot: root
        )
        XCTAssertTrue(mergeResult.hadConflicts)
        XCTAssertTrue(
            try git.listConflictedFiles(gitRoot: root).contains("a.txt")
        )

        try git.abortMerge(gitRoot: root)
        XCTAssertTrue(try git.listConflictedFiles(gitRoot: root).isEmpty)
    }

    func testPreflightCreateWorktreeRejectsMissingBaseBranch() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let branch = "solocode/worktree-\(UUID().uuidString.prefix(6))"
        let worktreePath = repo
            .deletingLastPathComponent()
            .appendingPathComponent("repo-worktrees")
            .appendingPathComponent("missing-base")

        XCTAssertThrowsError(
            try git.preflightCreateWorktree(
                gitRoot: root,
                branchName: branch,
                fromBranch: "missing-base",
                worktreePath: worktreePath.path
            )
        )
    }

    func testPreflightCreateWorktreeRejectsOccupiedPath() throws {
        let repo = try XCTUnwrap(repoURL)
        let root = try git.resolveGitRoot(from: repo.path)
        let branch = "solocode/worktree-\(UUID().uuidString.prefix(6))"
        let baseBranch = try git.currentBranch(gitRoot: root)
        let worktreePath = repo
            .deletingLastPathComponent()
            .appendingPathComponent("repo-worktrees")
            .appendingPathComponent("occupied-path")

        try FileManager.default.createDirectory(
            at: worktreePath,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try git.preflightCreateWorktree(
                gitRoot: root,
                branchName: branch,
                fromBranch: baseBranch,
                worktreePath: worktreePath.path
            )
        )
    }

    private func countAddedLines(in diff: GitFileDiff) -> Int {
        diff.chunks
            .flatMap(\.lines)
            .reduce(into: 0) { count, line in
                guard line.hasPrefix("+"),
                      !line.hasPrefix("+++"),
                      !line.hasPrefix("@@") else { return }
                count += 1
            }
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw NSError(
                domain: "GitServiceTests",
                code: Int(p.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    git \(args.joined(separator: " ")) failed (\(p.terminationStatus))
                    stdout: \(stdout)
                    stderr: \(stderr)
                    """
                ]
            )
        }
    }
}
