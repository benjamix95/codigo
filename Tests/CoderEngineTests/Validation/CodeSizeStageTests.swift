import XCTest
@testable import CoderEngine

final class CodeSizeStageTests: XCTestCase {
    func testPassesAtBoundary300Lines() async throws {
        let repo = try makeRepo()
        let file = "Engine/CoderEngine/Sources/Validation/Boundary.swift"
        try write(lines: 300, to: repo.appendingPathComponent(file))

        let result = await CodeSizeStage().run(
            context: ValidationContext(trigger: .gitCommit, workspaceRoot: repo, touchedFiles: [file]),
            profile: .gitCommit,
            descriptor: descriptor()
        )

        XCTAssertEqual(result.status, .passed)
    }

    func testFailsWhenNewFileExceeds300Lines() async throws {
        let repo = try makeRepo()
        let file = "Engine/CoderEngine/Sources/Validation/Oversized.swift"
        try write(lines: 301, to: repo.appendingPathComponent(file))

        let result = await CodeSizeStage().run(
            context: ValidationContext(trigger: .gitCommit, workspaceRoot: repo, touchedFiles: [file]),
            profile: .gitCommit,
            descriptor: descriptor()
        )

        XCTAssertEqual(result.status, .failed)
    }

    func testFailsWhenTouchedLegacyFileStillGrowsAboveLimit() async throws {
        let repo = try makeRepo()
        let file = "Engine/CoderEngine/Sources/Validation/Legacy.swift"
        let fileURL = repo.appendingPathComponent(file)
        try write(lines: 301, to: fileURL)
        try git(["add", "."], in: repo)
        try git(["commit", "-m", "initial"], in: repo)
        try write(lines: 302, to: fileURL)

        let result = await CodeSizeStage().run(
            context: ValidationContext(trigger: .gitCommit, workspaceRoot: repo, touchedFiles: [file]),
            profile: .gitCommit,
            descriptor: descriptor()
        )

        XCTAssertEqual(result.status, .failed)
    }

    private func makeRepo() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("validation-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Engine/CoderEngine/Sources/Validation"),
            withIntermediateDirectories: true
        )
        try git(["init"], in: root)
        try git(["config", "user.name", "Solo Code Tests"], in: root)
        try git(["config", "user.email", "tests@solocode.local"], in: root)
        return root
    }

    private func write(lines: Int, to url: URL) throws {
        let content = (0..<lines).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ args: [String], in root: URL) throws {
        _ = try ProcessRunner.runCollectingSync(
            executable: "/usr/bin/git",
            arguments: args,
            workingDirectory: root
        )
    }

    private func descriptor() -> ProjectValidationDescriptor {
        ProjectValidationDescriptor(
            version: 1,
            workspace: "Solo Code.xcworkspace",
            localScheme: "Solo Code-Debug",
            releaseScheme: "Solo Code-Release",
            destination: "platform=macOS",
            testPlan: nil,
            codeFileGlobs: ["Engine/**/*.swift"],
            excludedCodePaths: ["App/**/Resources/**"],
            securitySensitivePrefixes: [],
            testGroups: []
        )
    }
}
