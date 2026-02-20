import XCTest
@testable import CoderIDE

final class GitServiceTests: XCTestCase {
    private var repoURL: URL!
    private let git = GitService()

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("git-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repoURL.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: repoURL.path)
        try runGit(["config", "user.name", "Git Test"], cwd: repoURL.path)
        try "hello".write(to: repoURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], cwd: repoURL.path)
        try runGit(["commit", "-m", "init"], cwd: repoURL.path)
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try super.tearDownWithError()
    }

    func testBranchAndStatusAndCommit() throws {
        let root = try git.resolveGitRoot(from: repoURL.path)
        let current = try git.currentBranch(gitRoot: root)
        XCTAssertFalse(current.isEmpty)
        let branches = try git.listLocalBranches(gitRoot: root)
        XCTAssertTrue(branches.contains(where: { $0.isCurrent }))

        try "change".write(to: repoURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let status = try git.status(gitRoot: root)
        XCTAssertGreaterThan(status.changedFiles, 0)

        let commit = try git.commit(gitRoot: root, message: "chore: update file", includeUnstaged: true)
        XCTAssertFalse(commit.sha.isEmpty)
        XCTAssertEqual(commit.subject, "chore: update file")
    }

    func testPushWithoutRemoteFails() throws {
        let root = try git.resolveGitRoot(from: repoURL.path)
        XCTAssertThrowsError(try git.push(gitRoot: root, branch: try git.currentBranch(gitRoot: root)))
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
