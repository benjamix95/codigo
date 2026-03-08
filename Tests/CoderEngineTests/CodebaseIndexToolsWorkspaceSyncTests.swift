import XCTest
@testable import CoderEngine

final class CodebaseIndexToolsWorkspaceSyncTests: XCTestCase {
    func testExecuteReindexesWhenWorkspacePathsChange() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codebase-index-tools-\(UUID().uuidString)", isDirectory: true)
        let workspaceA = root.appendingPathComponent("workspace-a", isDirectory: true)
        let workspaceB = root.appendingPathComponent("workspace-b", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "struct FirstWorkspaceSymbol {}".write(
            to: workspaceA.appendingPathComponent("First.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct SecondWorkspaceSymbol {}".write(
            to: workspaceB.appendingPathComponent("Second.swift"),
            atomically: true,
            encoding: .utf8
        )

        let index = CodebaseIndex()
        let tools = CodebaseIndexTools(index: index)

        _ = await tools.execute(
            toolName: "index_status",
            args: [:],
            callId: "call-a",
            workspacePaths: [workspaceA]
        )

        var status = await index.status()
        XCTAssertEqual(status.workspacePaths, [workspaceA.path])

        _ = await tools.execute(
            toolName: "index_status",
            args: [:],
            callId: "call-b",
            workspacePaths: [workspaceB]
        )

        status = await index.status()
        XCTAssertEqual(status.workspacePaths, [workspaceB.path])
    }
}
