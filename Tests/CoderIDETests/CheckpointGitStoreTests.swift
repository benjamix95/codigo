import XCTest
@testable import CoderIDE

final class CheckpointGitStoreTests: XCTestCase {
    private var repoURL: URL?
    private let gitStore = ConversationCheckpointGitStore()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
        let repo = base.appendingPathComponent("checkpoint-git-\(UUID().uuidString)")
        repoURL = repo
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try run(["init"], cwd: repo.path)
        try run(["config", "user.email", "test@example.com"], cwd: repo.path)
        try run(["config", "user.name", "Checkpoint Test"], cwd: repo.path)
        try "v1".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try run(["add", "."], cwd: repo.path)
        try run(["commit", "-m", "init"], cwd: repo.path)
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try super.tearDownWithError()
    }

    func testCaptureAndRestoreTrackedAndUntracked() throws {
        let convId = UUID()
        let repo = try XCTUnwrap(repoURL)
        let snap = try gitStore.captureSnapshot(conversationId: convId, workingDirectory: repo.path)

        try "v2".write(to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "tmp".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        try gitStore.restoreSnapshot(ref: snap.ref, gitRoot: snap.gitRoot)

        let tracked = try String(contentsOf: repo.appendingPathComponent("tracked.txt"), encoding: .utf8)
        XCTAssertEqual(tracked, "v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("untracked.txt").path))
    }

    func testRestoreFailsForInvalidRef() throws {
        let repo = try XCTUnwrap(repoURL)
        XCTAssertThrowsError(try gitStore.restoreSnapshot(ref: "deadbeef", gitRoot: repo.path))
    }

    private func run(_ args: [String], cwd: String) throws {
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
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "CheckpointGitStoreTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    git \(args.joined(separator: " ")) failed (\(process.terminationStatus))
                    stdout: \(stdout)
                    stderr: \(stderr)
                    """
                ]
            )
        }
    }
}
