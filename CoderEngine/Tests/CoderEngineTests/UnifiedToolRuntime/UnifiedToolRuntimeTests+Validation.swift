import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testResolvePathReturnsNilWhenWorkspaceListIsEmpty() async {
        let runtime = UnifiedToolRuntime()

        let resolved = await runtime.resolvePath(
            "Sources/App.swift",
            workspacePaths: [],
            preferredRoot: nil,
            sandboxMode: "workspace-write"
        )

        XCTAssertNil(resolved)
    }

    func testResolvePathAllowsAbsolutePathOnlyInsideWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let workspace = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let file = workspace.appendingPathComponent("inside.swift")
        try "let x = 1".write(to: file, atomically: true, encoding: .utf8)

        let resolved = await runtime.resolvePath(
            file.path,
            workspacePaths: [workspace.path],
            preferredRoot: workspace.path,
            sandboxMode: "workspace-write"
        )

        XCTAssertEqual(resolved, file.standardizedFileURL.path)
    }
}
