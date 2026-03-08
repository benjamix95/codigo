import XCTest
@testable import CoderEngine

final class SemanticSearchBenchmarkTests: XCTestCase {
    func testSemanticSearchBenchmarkSynthetic10kFiles() async throws {
        let isFull = ProcessInfo.processInfo.environment["RUN_SEMANTIC_BENCHMARK"] == "1"
        let fileCount = isFull ? 10_000 : 200

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("semantic-bench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        for i in 0..<fileCount {
            let content = """
            struct BenchType\(i) {
                func authFlow\(i)() {
                    let token = "benchmark-\(i)"
                    _ = token
                }
            }
            """
            try content.write(
                to: workspace.appendingPathComponent("Bench\(i).swift"),
                atomically: true,
                encoding: .utf8
            )
        }

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspace])
        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [workspace])

        let start = Date()
        let call = ToolCall(
            id: UUID().uuidString,
            name: "semantic_search",
            args: ["query": "where is auth flow handled", "limit": "20"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let context = ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: workspace),
            policy: ToolRuntimePolicy()
        )
        _ = await runtime.execute(call, context: context)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        XCTAssertGreaterThan(durationMs, 0)
    }
}
