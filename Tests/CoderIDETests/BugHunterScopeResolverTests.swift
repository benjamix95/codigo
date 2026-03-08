import XCTest
@testable import CoderIDE

final class BugHunterScopeResolverTests: XCTestCase {
    private var repoURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bughunter-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        _ = try run("git", "init", cwd: repoURL.path)
        _ = try run("git", "config", "user.email", "tests@example.com", cwd: repoURL.path)
        _ = try run("git", "config", "user.name", "Tests", cwd: repoURL.path)

        try "one".write(to: repoURL.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        _ = try run("git", "add", "A.swift", cwd: repoURL.path)
        _ = try run("git", "commit", "-m", "first", cwd: repoURL.path)

        try "two".write(to: repoURL.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        _ = try run("git", "add", "A.swift", cwd: repoURL.path)
        _ = try run("git", "commit", "-m", "second", cwd: repoURL.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoURL)
        repoURL = nil
        try super.tearDownWithError()
    }

    func testCorrelatedCommitWindowIncludesPrimaryCommitFiles() throws {
        let head = try run("git", "rev-parse", "HEAD", cwd: repoURL.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolver = BugHunterScopeResolver()
        let window = try resolver.correlatedCommitWindow(
            gitRoot: repoURL.path,
            primaryCommit: head,
            maxCount: 5
        )

        XCTAssertEqual(window.primaryCommit, head)
        XCTAssertTrue(window.files.contains("A.swift"))
    }

    private func run(_ executable: String, _ args: String..., cwd: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "BugHunterScopeResolverTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
        }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
