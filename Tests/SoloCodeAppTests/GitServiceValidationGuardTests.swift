import XCTest
@testable import CoderIDE

final class GitServiceValidationGuardTests: XCTestCase {
    func testCommitRejectsUnstagedModeImmediately() async throws {
        let root = try makeRepo()
        let fileURL = root.appendingPathComponent("file.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            _ = try await GitService().commit(
                gitRoot: root.path,
                message: "chore: invalid",
                includeUnstaged: true
            )
            XCTFail("Expected unstaged guard")
        } catch let error as GitServiceError {
            guard case .unstagedCommitNotAllowed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("git-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let git = GitService()
        _ = try git.runCommand(executable: "/usr/bin/git", args: ["init"], cwd: root.path)
        return root
    }
}
