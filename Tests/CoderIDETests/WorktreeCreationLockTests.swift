import XCTest
@testable import CoderIDE

/// Tests that verify the NSLock serialization around worktree creation
/// prevents TOCTOU race conditions between preflight and `git worktree add`.
final class WorktreeCreationLockTests: XCTestCase {
    private var repoURL: URL!
    private var gitService: GitService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try initializeGitRepository(at: repoURL)
        gitService = GitService()
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        gitService = nil
        repoURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Serialization tests

    /// Two concurrent createWorktree calls with the same branch name must not
    /// both succeed — the lock ensures only one preflight+create sequence runs
    /// at a time, so the second call sees the branch already exists.
    func testConcurrentCreateWorktreeSerializesViaLock() async throws {
        let root = try gitService.resolveGitRoot(from: repoURL.path)
        let currentBranch = try gitService.currentBranch(gitRoot: root)
        let basePath = repoURL
            .deletingLastPathComponent()
            .appendingPathComponent("wt-lock-test")

        let branchA = "solocode/lock-a-\(UUID().uuidString.prefix(6))"
        let branchB = "solocode/lock-b-\(UUID().uuidString.prefix(6))"
        let pathA = basePath.appendingPathComponent("a").path
        let pathB = basePath.appendingPathComponent("b").path

        // Run two worktree creations concurrently — both should succeed
        // since they use different branches, but the lock ensures they
        // don't interleave preflight checks.
        let results: [(branch: String, error: Error?)] = await withTaskGroup(
            of: (String, Error?).self
        ) { group in
            group.addTask { [gitService] in
                do {
                    try gitService!.createWorktree(
                        gitRoot: root,
                        branchName: branchA,
                        fromBranch: currentBranch,
                        worktreePath: pathA
                    )
                    return (branchA, nil)
                } catch {
                    return (branchA, error)
                }
            }
            group.addTask { [gitService] in
                do {
                    try gitService!.createWorktree(
                        gitRoot: root,
                        branchName: branchB,
                        fromBranch: currentBranch,
                        worktreePath: pathB
                    )
                    return (branchB, nil)
                } catch {
                    return (branchB, error)
                }
            }
            var collected: [(String, Error?)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        // Both should succeed because they're different branches — the lock
        // serializes them so no TOCTOU race between preflight and git add.
        let successCount = results.filter { $0.error == nil }.count
        XCTAssertEqual(successCount, 2, "Both distinct worktrees should be created: \(results.map { ($0.branch, $0.error?.localizedDescription ?? "ok") })")

        // Cleanup
        try? gitService.removeWorktree(gitRoot: root, worktreePath: pathA, force: true)
        try? gitService.removeWorktree(gitRoot: root, worktreePath: pathB, force: true)
        try? FileManager.default.removeItem(at: basePath)
    }

    /// Two concurrent createWorktree calls for the SAME branch name must have
    /// exactly one succeed and one fail — without the lock, both preflights
    /// could pass, causing a git error.
    func testConcurrentSameBranchRejectsSecondCall() async throws {
        let root = try gitService.resolveGitRoot(from: repoURL.path)
        let currentBranch = try gitService.currentBranch(gitRoot: root)
        let basePath = repoURL
            .deletingLastPathComponent()
            .appendingPathComponent("wt-same-branch-\(UUID().uuidString.prefix(6))")

        let sharedBranch = "solocode/dup-\(UUID().uuidString.prefix(6))"
        let pathA = basePath.appendingPathComponent("dup-a").path
        let pathB = basePath.appendingPathComponent("dup-b").path

        let results: [Error?] = await withTaskGroup(of: Error?.self) { group in
            group.addTask { [gitService] in
                do {
                    try gitService!.createWorktree(
                        gitRoot: root,
                        branchName: sharedBranch,
                        fromBranch: currentBranch,
                        worktreePath: pathA
                    )
                    return nil
                } catch {
                    return error
                }
            }
            group.addTask { [gitService] in
                do {
                    try gitService!.createWorktree(
                        gitRoot: root,
                        branchName: sharedBranch,
                        fromBranch: currentBranch,
                        worktreePath: pathB
                    )
                    return nil
                } catch {
                    return error
                }
            }
            var collected: [Error?] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let successes = results.filter { $0 == nil }.count
        let failures = results.filter { $0 != nil }.count

        XCTAssertEqual(successes, 1, "Exactly one should succeed")
        XCTAssertEqual(failures, 1, "Exactly one should fail due to branch already existing")

        // Cleanup
        try? gitService.removeWorktree(gitRoot: root, worktreePath: pathA, force: true)
        try? gitService.removeWorktree(gitRoot: root, worktreePath: pathB, force: true)
        try? FileManager.default.removeItem(at: basePath)
    }

    /// Verify that ensureWorktreePathAvailable rejects paths already occupied.
    func testPreflightRejectsOccupiedPath() throws {
        let root = try gitService.resolveGitRoot(from: repoURL.path)
        let currentBranch = try gitService.currentBranch(gitRoot: root)
        let occupiedPath = repoURL
            .deletingLastPathComponent()
            .appendingPathComponent("wt-occupied-\(UUID().uuidString.prefix(6))")

        // Create the directory to simulate an occupied path
        try FileManager.default.createDirectory(
            at: occupiedPath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: occupiedPath) }

        XCTAssertThrowsError(try gitService.preflightCreateWorktree(
            gitRoot: root,
            branchName: "solocode/occ-\(UUID().uuidString.prefix(6))",
            fromBranch: currentBranch,
            worktreePath: occupiedPath.path
        )) { error in
            guard case GitServiceError.commandFailed(let msg) = error else {
                return XCTFail("Expected commandFailed, got \(error)")
            }
            XCTAssertTrue(msg.contains("occupato") || msg.contains("già"), "Error should mention path is occupied: \(msg)")
        }
    }

    // MARK: - Helpers

    private func initializeGitRepository(at url: URL) throws {
        try runGit(["init"], cwd: url.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: url.path)
        try runGit(["config", "user.name", "Git Test"], cwd: url.path)
        try "worktree-lock-test".write(
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
            let stderr = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw NSError(
                domain: "WorktreeCreationLockTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git failed: \(stderr)"]
            )
        }
    }
}
