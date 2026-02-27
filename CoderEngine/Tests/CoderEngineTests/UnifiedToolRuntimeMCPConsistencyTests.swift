import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeMCPConsistencyTests: XCTestCase {

    private func makeTmpWorkspace() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("codigo-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func extractLastPayload(_ events: [StreamEvent]) -> [String: String]? {
        for event in events.reversed() {
            if case .raw(_, let payload) = event {
                return payload
            }
        }
        return nil
    }

    private func makeCall(
        name: String,
        args: [String: String] = [:],
        workspace: URL
    ) -> (ToolCall, ToolExecutionContext) {
        let call = ToolCall(
            id: UUID().uuidString,
            name: name,
            args: args,
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        return (call, ctx)
    }

    func testGrepValidationMentionsPatternOrQueryAlias() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "grep", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        let message = completed?["detail"] ?? completed?["output"] ?? ""
        XCTAssertTrue(message.contains("pattern (or query) is required"))
    }

    func testFindFilesSupportsPathScopeAlias() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let scopeA = tmp.appendingPathComponent("ScopeA", isDirectory: true)
        let scopeB = tmp.appendingPathComponent("ScopeB", isDirectory: true)
        try FileManager.default.createDirectory(at: scopeA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scopeB, withIntermediateDirectories: true)

        try "struct ScopeAFile {}".write(
            to: scopeA.appendingPathComponent("ScopedMatch.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct ScopeBFile {}".write(
            to: scopeB.appendingPathComponent("ScopedMatch.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, ctx) = makeCall(
            name: "find_files",
            args: ["pattern": "ScopedMatch.swift", "path": "ScopeA"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("ScopeA/ScopedMatch.swift"), "Output find_files inatteso: \(output)")
        XCTAssertFalse(output.contains("ScopeB/ScopedMatch.swift"), "Output find_files inatteso: \(output)")
    }

    func testCodebaseSearchSupportsPathScopeAlias() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let scopeA = tmp.appendingPathComponent("ScopeA", isDirectory: true)
        let scopeB = tmp.appendingPathComponent("ScopeB", isDirectory: true)
        try FileManager.default.createDirectory(at: scopeA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scopeB, withIntermediateDirectories: true)

        try "struct SharedScopedSymbol {}".write(
            to: scopeA.appendingPathComponent("ScopedSymbol.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "struct SharedScopedSymbol {}".write(
            to: scopeB.appendingPathComponent("ScopedSymbol.swift"),
            atomically: true,
            encoding: .utf8
        )

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, ctx) = makeCall(
            name: "codebase_search",
            args: ["query": "SharedScopedSymbol", "path": "ScopeA"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("ScopeA/ScopedSymbol.swift"), "Output codebase_search inatteso: \(output)")
        XCTAssertFalse(output.contains("ScopeB/ScopedSymbol.swift"), "Output codebase_search inatteso: \(output)")
    }
}
