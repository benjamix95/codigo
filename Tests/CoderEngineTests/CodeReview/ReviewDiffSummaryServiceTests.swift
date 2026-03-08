import XCTest
@testable import CoderEngine

final class ReviewDiffSummaryServiceTests: XCTestCase {
    func testRenderSummaryUsesAgainstRefRangeForRenamedFiles() throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }

        try runGit(["init", "-q"], in: repo)
        try runGit(["config", "user.email", "review-tests@example.com"], in: repo)
        try runGit(["config", "user.name", "Review Tests"], in: repo)

        let sourceDir = repo.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let oldFile = sourceDir.appendingPathComponent("Old.swift")
        try "print(\"before\")\n".write(to: oldFile, atomically: true, encoding: .utf8)
        try runGit(["add", "Sources/Old.swift"], in: repo)
        try runGit(["commit", "-qm", "initial"], in: repo)

        try runGit(["mv", "Sources/Old.swift", "Sources/New.swift"], in: repo)
        let newFile = sourceDir.appendingPathComponent("New.swift")
        try "print(\"before\")\nprint(\"after\")\n".write(to: newFile, atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "rename"], in: repo)

        let snapshot = makeSnapshot(
            scope: ReviewSessionScope(
                type: .againstRef,
                files: ["Sources/New.swift"],
                ref: "HEAD~1"
            ),
            workspacePath: repo.path
        )

        let summary = ReviewDiffSummaryService.renderSummary(
            snapshot: snapshot,
            workspacePath: repo
        )

        XCTAssertTrue(summary.contains("Sources/New.swift"))
        XCTAssertTrue(summary.contains("+1 / -0"))
    }

    func testRenderSummaryCountsUntrackedFilesInUncommittedScope() throws {
        let repo = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repo) }

        try runGit(["init", "-q"], in: repo)
        try runGit(["config", "user.email", "review-tests@example.com"], in: repo)
        try runGit(["config", "user.name", "Review Tests"], in: repo)
        try "# Temp repo\n".write(
            to: repo.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], in: repo)
        try runGit(["commit", "-qm", "initial"], in: repo)

        let untrackedFile = repo.appendingPathComponent("scratch.swift")
        try "let a = 1\nlet b = 2\n".write(
            to: untrackedFile,
            atomically: true,
            encoding: .utf8
        )

        let snapshot = makeSnapshot(
            scope: ReviewSessionScope(type: .uncommitted, files: ["scratch.swift"]),
            workspacePath: repo.path
        )

        let summary = ReviewDiffSummaryService.renderSummary(
            snapshot: snapshot,
            workspacePath: repo
        )

        XCTAssertTrue(summary.contains("scratch.swift"))
        XCTAssertTrue(summary.contains("+2 / -0"))
    }

    private func makeRepository() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-diff-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSnapshot(
        scope: ReviewSessionScope,
        workspacePath: String
    ) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .fixing,
            stage: .fixing,
            findings: [],
            events: [],
            config: .default,
            scope: scope,
            workspacePath: workspacePath,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: nil,
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: error, encoding: .utf8) ?? "git failed"
            throw NSError(domain: "ReviewDiffSummaryServiceTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        return String(data: output, encoding: .utf8) ?? ""
    }
}
