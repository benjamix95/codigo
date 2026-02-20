import XCTest
@testable import CoderIDE

final class CheckpointGitStoreTests: XCTestCase {
    private var repoURL: URL!
    private let gitStore = ConversationCheckpointGitStore()

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = FileManager.default.temporaryDirectory
        repoURL = base.appendingPathComponent("checkpoint-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try run(["init"], cwd: repoURL.path)
        try run(["config", "user.email", "test@example.com"], cwd: repoURL.path)
        try run(["config", "user.name", "Checkpoint Test"], cwd: repoURL.path)
        try "v1".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try run(["add", "."], cwd: repoURL.path)
        try run(["commit", "-m", "init"], cwd: repoURL.path)
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try super.tearDownWithError()
    }

    func testCaptureAndRestoreTrackedAndUntracked() throws {
        let convId = UUID()
        let snap = try gitStore.captureSnapshot(conversationId: convId, workingDirectory: repoURL.path)

        try "v2".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try "tmp".write(to: repoURL.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)

        try gitStore.restoreSnapshot(ref: snap.ref, gitRoot: snap.gitRoot)

        let tracked = try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8)
        XCTAssertEqual(tracked, "v1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("untracked.txt").path))
    }

    func testRestoreFailsForInvalidRef() throws {
        XCTAssertThrowsError(try gitStore.restoreSnapshot(ref: "deadbeef", gitRoot: repoURL.path))
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
