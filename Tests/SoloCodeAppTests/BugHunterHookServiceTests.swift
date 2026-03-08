import XCTest
@testable import CoderIDE

final class BugHunterHookServiceTests: XCTestCase {
    private var repoURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bughunter-hook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".git/hooks"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoURL)
        repoURL = nil
        try super.tearDownWithError()
    }

    func testInstallAndUninstallManagedHook() throws {
        let service = BugHunterHookService()
        try service.installPostCommitHook(gitRoot: repoURL.path)

        let hook = try String(
            contentsOf: repoURL.appendingPathComponent(".git/hooks/post-commit"),
            encoding: .utf8
        )
        XCTAssertTrue(hook.contains("post-commit.coderide"))

        try service.uninstallPostCommitHook(gitRoot: repoURL.path)
        let hookExists = FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent(".git/hooks/post-commit").path
        )
        XCTAssertFalse(hookExists)
    }
}
