import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testSemanticSearchBackfillsVectorStoreWhenSemanticIndexExistsButTableIsEmpty() async throws {
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = """
        struct AuthFlowVectorBackfill {
            func handleLogin() {
                print("vector backfill auth flow")
            }
        }
        """
        let fileURL = tmp.appendingPathComponent("AuthFlowVectorBackfill.swift")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [tmp])

        try PostgresPersistenceStore.shared.deleteAllEmbeddings()
        let initialStats = try PostgresPersistenceStore.shared.vectorSearchTableStats()
        XCTAssertEqual(initialStats.rowCount, 0)

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "where is auth flow handled", "limit": "5"],
            workspace: tmp
        )
        _ = await runtime.execute(call, context: ctx)

        var finalStats = try PostgresPersistenceStore.shared.vectorSearchTableStats()
        if finalStats.rowCount == 0 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            finalStats = try PostgresPersistenceStore.shared.vectorSearchTableStats()
        }

        XCTAssertGreaterThan(finalStats.rowCount, 0)
        XCTAssertGreaterThan(finalStats.fileCount, 0)
    }
}
