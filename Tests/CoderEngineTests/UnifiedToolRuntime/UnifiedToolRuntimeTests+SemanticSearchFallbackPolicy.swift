import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testSemanticSearchSkipsGrepFallbackWhenIndexedHitsAreSufficient() async throws {
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let files: [(String, String)] = [
            ("AuthLoginFlow.swift", "struct AuthLoginFlow { func handleLogin() { print(\"authentication login\") } }"),
            ("AuthSessionFlow.swift", "struct AuthSessionFlow { func refreshSession() { print(\"authentication login\") } }"),
            ("AuthCredentialStore.swift", "struct AuthCredentialStore { func storeCredential() { print(\"authentication login\") } }"),
        ]
        for (name, contents) in files {
            try contents.write(
                to: tmp.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [tmp])
        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])

        let (semanticCall, semanticContext) = makeCall(
            name: "semantic_search",
            args: ["query": "authentication login", "limit": "3"],
            workspace: tmp
        )
        let semanticEvents = await runtime.execute(semanticCall, context: semanticContext)
        let semanticPayload = extractLastPayload(semanticEvents)

        XCTAssertEqual(semanticPayload?["status"], "completed")
        XCTAssertFalse((semanticPayload?["detail"] ?? "").contains("grep fallback"))

        let (healthCall, healthContext) = makeCall(
            name: "search_health_check",
            workspace: tmp
        )
        let healthEvents = await runtime.execute(healthCall, context: healthContext)
        let healthPayload = extractLastPayload(healthEvents)

        XCTAssertEqual(healthPayload?["status"], "completed")
        XCTAssertEqual(healthPayload?["grep_cache_entries"], "0")
    }
}
