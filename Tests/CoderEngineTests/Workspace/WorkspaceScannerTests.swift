import XCTest
@testable import CoderEngine

final class WorkspaceScannerTests: XCTestCase {
    func testListSourceFilesUsesGitInventoryWhenWorkspaceIsRepository() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-scanner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        try runGit(["init"], in: workspace)
        try "print(1)\n".write(
            to: workspace.appendingPathComponent("tracked.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: workspace.appendingPathComponent("Ignored"),
            withIntermediateDirectories: true
        )
        try "Ignored/\n".write(
            to: workspace.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "print(2)\n".write(
            to: workspace.appendingPathComponent("new.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "print(3)\n".write(
            to: workspace.appendingPathComponent("Ignored/hidden.swift"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.swift", ".gitignore"], in: workspace)

        let files = WorkspaceScanner.listSourceFiles(workspacePath: workspace)

        XCTAssertEqual(files, ["new.swift", "tracked.swift"])
    }

    private func runGit(_ arguments: [String], in workspace: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
