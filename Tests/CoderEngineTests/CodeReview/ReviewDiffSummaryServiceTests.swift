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

final class ReviewCandidateVerificationServiceTests: XCTestCase {
    private var workspaceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-candidate-verifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let path = reviewCoreLibraryPath(from: #filePath)
        if FileManager.default.fileExists(atPath: path) {
            setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        }
        ReviewCoreBridge.resetForTests()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspaceURL)
        workspaceURL = nil
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        try super.tearDownWithError()
    }

    func testMissingLineContextStaysInconclusiveEvenWhenEvidenceExistsInFile() throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Review core Rust non disponibile in build/lib")
        }
        let fileURL = workspaceURL.appendingPathComponent("Sample.swift")
        try """
        let token = "SECRET_MATCH"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Sample.swift",
            lineNumber: nil,
            message: "Potential issue",
            evidence: "SECRET_MATCH"
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Sample.swift"]
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.method, "file_evidence_search")
    }

    func testSemanticRiskHeuristicDoesNotPromoteToVerified() throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Review core Rust non disponibile in build/lib")
        }
        let fileURL = workspaceURL.appendingPathComponent("Risky.swift")
        try """
        let value = try! expensiveCall()
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .critical,
            category: .regression,
            origin: .reviewer,
            filePath: "Risky.swift",
            lineNumber: 1,
            message: "force-try can crash the flow",
            evidence: nil
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Risky.swift"]
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.method, "semantic_risk_match")
    }

    func testExactLineEvidenceStillPromotesToVerified() throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Review core Rust non disponibile in build/lib")
        }
        let fileURL = workspaceURL.appendingPathComponent("Exact.swift")
        try """
        let apiKey = "abc"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let candidate = ReviewCandidate(
            severity: .warning,
            category: .security,
            origin: .reviewer,
            filePath: "Exact.swift",
            lineNumber: 1,
            message: "Secret in source",
            evidence: #"apiKey = "abc""#
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Exact.swift"]
        )

        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.method, "line_evidence_match")
    }

    func testVerificationFailsExplicitlyWhenRustCoreIsDisabled() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }
        ReviewCoreBridge.resetForTests()

        let candidate = ReviewCandidate(
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "Sample.swift",
            lineNumber: 1,
            message: "Potential issue",
            evidence: "SECRET_MATCH"
        )

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: ["Sample.swift"]
        )

        XCTAssertEqual(result.status, .inconclusive)
        XCTAssertEqual(result.method, "rust_core_unavailable")
        XCTAssertEqual(
            result.report,
            "La verifica automatica richiede il review core Rust. Nessun fallback Swift locale è consentito."
        )
    }
}

private func reviewCoreLibraryPath(from sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    return sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Native/RustCore/build/lib/libsolocode_rust_core.dylib")
        .path
}
