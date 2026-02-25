import XCTest
@testable import CoderIDE

final class FileChangePreviewResolverTests: XCTestCase {
    private var repoURL: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent(
            "file-preview-resolver-\(UUID().uuidString)"
        )
        repoURL = repo
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo.path)
        try runGit(["config", "user.name", "Resolver Test"], cwd: repo.path)

        let tracked = repo.appendingPathComponent("Tracked.swift")
        try "let value = 1\n".write(to: tracked, atomically: true, encoding: .utf8)
        try runGit(["add", "Tracked.swift"], cwd: repo.path)
        try runGit(["commit", "-m", "init"], cwd: repo.path)
    }

    override func tearDownWithError() throws {
        if let repoURL {
            try? FileManager.default.removeItem(at: repoURL)
        }
        try super.tearDownWithError()
    }

    func testResolvePreviewPrefersPayloadDiff() async throws {
        let repo = try XCTUnwrap(repoURL)
        let resolver = FileChangePreviewResolver()

        let change = makeChange(
            path: "Tracked.swift",
            kind: .edited,
            diffPreview: "@@ -1 +1 @@\n-let value = 1\n+let value = 2"
        )

        let result = await resolver.resolvePreview(for: change, workspaceHints: [repo.path])

        guard case .diff(let text) = result else {
            return XCTFail("Expected payload diff preview")
        }
        XCTAssertTrue(text.contains("+let value = 2"))
    }

    func testResolvePreviewFallsBackToGitDiff() async throws {
        let repo = try XCTUnwrap(repoURL)
        let tracked = repo.appendingPathComponent("Tracked.swift")
        try "let value = 2\n".write(to: tracked, atomically: true, encoding: .utf8)

        let resolver = FileChangePreviewResolver()
        let change = makeChange(path: "Tracked.swift", kind: .edited)

        let result = await resolver.resolvePreview(for: change, workspaceHints: [repo.path])

        guard case .diff(let text) = result else {
            return XCTFail("Expected git diff preview")
        }
        XCTAssertTrue(text.contains("+let value = 2"))
        XCTAssertTrue(text.contains("-let value = 1"))
    }

    func testResolvePreviewFallsBackToFileContentForCreatedFile() async throws {
        let repo = try XCTUnwrap(repoURL)
        let created = repo.appendingPathComponent("NewFile.swift")
        try "import Foundation\nlet created = true\n".write(to: created, atomically: true, encoding: .utf8)

        let resolver = FileChangePreviewResolver()
        let change = makeChange(path: "NewFile.swift", kind: .created, added: 2)

        let result = await resolver.resolvePreview(for: change, workspaceHints: [repo.path])

        guard case .fileContent(let text) = result else {
            return XCTFail("Expected file content fallback for created file")
        }
        XCTAssertTrue(text.contains("let created = true"))
    }

    func testResolvePreviewFallsBackToMetadataWhenNoPathExists() async {
        let resolver = FileChangePreviewResolver()
        let change = makeChange(path: nil, kind: .edited, added: 0, removed: 32)

        let result = await resolver.resolvePreview(for: change, workspaceHints: [])

        guard case .metadataOnly(let text) = result else {
            return XCTFail("Expected metadata fallback")
        }
        XCTAssertTrue(text.contains("Edited file"))
        XCTAssertTrue(text.contains("Lines: +0 -32"))
    }

    private func makeChange(
        path: String?,
        kind: ToolTraceFileChangeKind,
        added: Int = 0,
        removed: Int = 0,
        diffPreview: String? = nil
    ) -> ToolTraceFileChange {
        let basename = (path.map { ($0 as NSString).lastPathComponent } ?? "file")
        return ToolTraceFileChange(
            eventId: UUID(),
            path: path,
            basename: basename,
            kind: kind,
            added: added,
            removed: removed,
            diffPreview: diffPreview,
            rawOutput: nil,
            sequence: 1,
            timestamp: .now,
            isRunning: false
        )
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return
        }

        let out = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let err = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw NSError(
            domain: "FileChangePreviewResolverTests",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed: \(out) \(err)",
            ]
        )
    }
}
