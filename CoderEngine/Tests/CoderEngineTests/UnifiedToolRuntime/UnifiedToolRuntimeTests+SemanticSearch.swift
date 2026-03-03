import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    // MARK: - Semantic Search Tests

    func testSemanticSearchValidationRequiresQuery() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "semantic_search")
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testSemanticSearchEmptyQueryFails() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "semantic_search", args: ["query": "   "])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testSemanticSearchFindsFileByContent() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create files with known content
        let authFile = tmp.appendingPathComponent("AuthManager.swift")
        try "class AuthManager {\n    func handleLogin(user: String) {\n        // authentication logic\n    }\n}".write(to: authFile, atomically: true, encoding: .utf8)

        let dataFile = tmp.appendingPathComponent("DataStore.swift")
        try "struct DataStore {\n    func saveToDisk() {\n        // persistence logic\n    }\n}".write(to: dataFile, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "authentication login"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["tool"], "semantic_search")

        let output = completed?["output"] ?? ""
        // Should find auth-related content
        XCTAssertTrue(output.contains("Auth") || output.contains("login") || output.contains("authentication"),
                       "Semantic search should find auth-related code: \(output)")
    }

    func testSemanticSearchRespectsLimit() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create multiple files
        for i in 1...10 {
            let file = tmp.appendingPathComponent("File\(i).swift")
            try "func testFunction\(i)() { }".write(to: file, atomically: true, encoding: .utf8)
        }

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "testFunction", "limit": "3"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")

        let count = Int(completed?["count"] ?? "0") ?? 0
        XCTAssertLessThanOrEqual(count, 3, "Should respect limit parameter")
    }

    func testSemanticSearchLimitAliasTakesPriority() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        for i in 1...12 {
            let file = tmp.appendingPathComponent("LimitAlias\(i).swift")
            try "func limitAlias\(i)() { print(\"alias\") }".write(to: file, atomically: true, encoding: .utf8)
        }

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "limit alias", "num_results": "10", "limit": "2"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let count = Int(completed?["count"] ?? "0") ?? 0
        XCTAssertLessThanOrEqual(count, 2, "limit alias should cap results")
    }

    func testSemanticSearchFallbackSupportsMultipleTargetDirectories() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dirA = tmp.appendingPathComponent("DirA", isDirectory: true)
        let dirB = tmp.appendingPathComponent("DirB", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        try "func alphaMatch() { print(\"shared semantic token\") }".write(
            to: dirA.appendingPathComponent("Alpha.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "func betaMatch() { print(\"shared semantic token\") }".write(
            to: dirB.appendingPathComponent("Beta.swift"),
            atomically: true,
            encoding: .utf8
        )

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: [
                "query": "shared semantic token",
                "target_directories": "DirA,DirB",
                "limit": "10",
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("DirA/Alpha.swift"), "Expected hit from DirA")
        XCTAssertTrue(output.contains("DirB/Beta.swift"), "Expected hit from DirB")
    }

    func testSemanticSearchSupportsJSONArrayTargetDirectories() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dirA = tmp.appendingPathComponent("DirA", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try "func jsonScopeToken() { print(\"array target dirs\") }".write(
            to: dirA.appendingPathComponent("ArrayScope.swift"),
            atomically: true,
            encoding: .utf8
        )

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: [
                "query": "json scope token",
                "target_directories": #"["DirA"]"#,
                "limit": "5",
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""
        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("DirA/ArrayScope.swift"))
    }

    func testSemanticSearchReindexesWhenWorkspacePathsChange() async throws {
        let root = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }

        let workspaceA = root.appendingPathComponent("workspace-a", isDirectory: true)
        let workspaceB = root.appendingPathComponent("workspace-b", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceB, withIntermediateDirectories: true)

        try "struct WorkspaceAOnlySymbol {}".write(
            to: workspaceA.appendingPathComponent("First.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "func betaWorkspaceToken() { print(\"beta workspace token\") }".write(
            to: workspaceB.appendingPathComponent("Second.swift"),
            atomically: true,
            encoding: .utf8
        )

        let index = CodebaseIndex()
        _ = await index.indexWorkspace(paths: [workspaceA])

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [workspaceB])
        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "beta workspace token"],
            workspace: workspaceB
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let status = await index.status()
        XCTAssertEqual(status.workspacePaths, [workspaceB.path])
        XCTAssertTrue(
            (completed?["output"] ?? "").contains("Second.swift"),
            "Expected semantic search output to be refreshed for workspace-b"
        )
    }

    func testSemanticSearchNaturalLanguageRanksAuthBeforeGenericHandler() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        final class AuthenticationService {
            func handleAuthentication(_ token: String) -> Bool {
                authorizeUser(token)
            }
            private func authorizeUser(_ token: String) -> Bool { !token.isEmpty }
        }
        """.write(to: tmp.appendingPathComponent("AuthenticationService.swift"), atomically: true, encoding: .utf8)

        try """
        struct GenericHandler {
            func handle(_ input: String) -> Bool { !input.isEmpty }
        }
        """.write(to: tmp.appendingPathComponent("GenericHandler.swift"), atomically: true, encoding: .utf8)

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])
        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "where is auth handled", "limit": "5"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("1.") && output.contains("AuthenticationService.swift"), "Auth file should be ranked first: \(output)")
    }

    func testSemanticSearchSynonymQueriesMatchAuthAreaInRuntime() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        struct AccessControl {
            static func authenticationCheck() -> Bool { true }
        }
        """.write(to: tmp.appendingPathComponent("AccessControl.swift"), atomically: true, encoding: .utf8)

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])

        for query in ["auth", "authentication", "authorize"] {
            let (call, ctx) = makeCall(
                name: "semantic_search",
                args: ["query": query],
                workspace: tmp
            )
            let events = await runtime.execute(call, context: ctx)
            let completed = extractLastPayload(events)
            let output = completed?["output"] ?? ""

            XCTAssertEqual(completed?["status"], "completed")
            XCTAssertTrue(output.contains("AccessControl.swift"), "Expected auth hit for query '\(query)': \(output)")
        }
    }

    func testSemanticSearchFallbackUsesGrepWhenIndexUnavailable() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        try """
        func authorizeRequest() -> Bool {
            true
        }
        """.write(to: tmp.appendingPathComponent("FallbackAuth.swift"), atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "authorize request", "limit": "3"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue((completed?["detail"] ?? "").contains("grep fallback"))
        XCTAssertTrue(output.contains("FallbackAuth.swift"), "Fallback output should include matching file: \(output)")
    }

    func testSemanticSearchRejectsTargetDirectoryOutsideWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "auth", "target_directories": "/tmp"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testSemanticSearchRejectsTargetDirectoryTraversalOutsideWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "auth", "target_directories": "../"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testSemanticSearchTargetDirectoryFiltersSymbolHits() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dirA = tmp.appendingPathComponent("DirA", isDirectory: true)
        let dirB = tmp.appendingPathComponent("DirB", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        try "func AuthTargetSymbol() { print(\"A\") }".write(
            to: dirA.appendingPathComponent("AuthA.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "func AuthTargetSymbol() { print(\"B\") }".write(
            to: dirB.appendingPathComponent("AuthB.swift"),
            atomically: true,
            encoding: .utf8
        )

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "AuthTargetSymbol", "target_directories": "DirA", "limit": "10"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("DirA/AuthA.swift"), "Expected scoped hit in DirA: \(output)")
        XCTAssertFalse(output.contains("DirB/AuthB.swift"), "Scoped semantic search should exclude DirB hits: \(output)")
    }
}
