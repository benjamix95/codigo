import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testGrepMultiScopeProducesPreviewAndCountPayload() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dirA = tmp.appendingPathComponent("ScopeA", isDirectory: true)
        let dirB = tmp.appendingPathComponent("ScopeB", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try "let instantNeedle = 1\n".write(to: dirA.appendingPathComponent("One.swift"), atomically: true, encoding: .utf8)
        try "let instantNeedle = 2\n".write(to: dirB.appendingPathComponent("Two.swift"), atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "grep",
            args: ["query": "instantNeedle", "pathScope": "ScopeA,ScopeB"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["pathScope"], "ScopeA,ScopeB")
        XCTAssertFalse((completed?["previewLines"] ?? "").isEmpty)
        XCTAssertGreaterThan(Int(completed?["count"] ?? "0") ?? 0, 0)
    }

    func testReadSupportsOffsetAndLimitAliases() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("offset.txt")
        try "one\ntwo\nthree\nfour\nfive\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "read",
            args: ["path": file.path, "offset": "3", "limit": "2"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["detail"], "2 lines")
        let output = completed?["output"] ?? ""
        XCTAssertTrue(output.contains("3│three"))
        XCTAssertTrue(output.contains("4│four"))
        XCTAssertFalse(output.contains("2│two"))
    }

    func testReadRangeAcceptsStartLineAndEndLineAliases() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("range.txt")
        try "alpha\nbeta\ngamma\ndelta\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "read_range",
            args: ["path": file.path, "start_line": "2", "end_line": "3"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let output = completed?["output"] ?? ""
        XCTAssertTrue(output.contains("2: beta"))
        XCTAssertTrue(output.contains("3: gamma"))
        XCTAssertFalse(output.contains("1: alpha"))
    }

    func testGrepAcceptsPatternAlias() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("needle.swift")
        try "let patternNeedle = true\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "grep",
            args: ["pattern": "patternNeedle", "pathScope": "."],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertGreaterThan(Int(completed?["count"] ?? "0") ?? 0, 0)
    }

    func testGrepSandboxBlocksOutsideWorkspacePathScope() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-grep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }

        let outsideFile = outsideDir.appendingPathComponent("leak.txt")
        try "outside-secret".write(to: outsideFile, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "grep",
            args: ["query": "outside-secret", "pathScope": outsideDir.path],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
    }

    func testGlobPathScopeAliasProducesCountAndPreview() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let nested = tmp.appendingPathComponent("Sources/Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "struct Smoke {}\n".write(
            to: nested.appendingPathComponent("SubagentSmoke.swift"),
            atomically: true,
            encoding: .utf8
        )

        let (call, ctx) = makeCall(
            name: "glob",
            args: ["pattern": "**/Sources/**/*Subagent*", "pathScope": "."],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["pathScope"], tmp.path)
        XCTAssertGreaterThan(Int(completed?["count"] ?? "0") ?? 0, 0)
        XCTAssertFalse((completed?["previewLines"] ?? "").isEmpty)
    }

    func testIndexToolsAcceptLegacyAliases() async throws {
        let index = CodebaseIndex()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let symbolFile = tmp.appendingPathComponent("LegacyAlias.swift")
        try "struct LegacyAliasSymbol {}\n".write(to: symbolFile, atomically: true, encoding: .utf8)

        let runtime = UnifiedToolRuntime(index: index, workspacePaths: [tmp])

        let (findSymbolCall, findSymbolCtx) = makeCall(
            name: "find_symbol",
            args: ["name": "LegacyAliasSymbol"],
            workspace: tmp
        )
        let findSymbolEvents = await runtime.execute(findSymbolCall, context: findSymbolCtx)
        let findSymbolPayload = extractLastPayload(findSymbolEvents)
        XCTAssertEqual(findSymbolPayload?["status"], "completed")
        XCTAssertTrue((findSymbolPayload?["output"] ?? "").contains("LegacyAliasSymbol"))

        let (findFilesCall, findFilesCtx) = makeCall(
            name: "find_files",
            args: ["pattern": "LegacyAlias.swift"],
            workspace: tmp
        )
        let findFilesEvents = await runtime.execute(findFilesCall, context: findFilesCtx)
        let findFilesPayload = extractLastPayload(findFilesEvents)
        XCTAssertEqual(findFilesPayload?["status"], "completed")
        XCTAssertTrue((findFilesPayload?["output"] ?? "").contains("LegacyAlias.swift"))
    }

    func testIndexToolsInitializeLazilyWhenMissing() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("LazyIndex.swift")
        try "struct LazyIndexSymbol {}\n".write(to: file, atomically: true, encoding: .utf8)

        let before = await runtime.debugSnapshot()
        XCTAssertFalse(before.hasCodebaseIndex)

        let (findFilesCall, findFilesCtx) = makeCall(
            name: "find_files",
            args: ["pattern": "LazyIndex.swift"],
            workspace: tmp
        )
        let findFilesEvents = await runtime.execute(findFilesCall, context: findFilesCtx)
        let findFilesPayload = extractLastPayload(findFilesEvents)
        XCTAssertEqual(findFilesPayload?["status"], "completed")
        XCTAssertTrue((findFilesPayload?["output"] ?? "").contains("LazyIndex.swift"))

        let (searchCall, searchCtx) = makeCall(
            name: "codebase_search",
            args: ["query": "LazyIndexSymbol"],
            workspace: tmp
        )
        let searchEvents = await runtime.execute(searchCall, context: searchCtx)
        let searchPayload = extractLastPayload(searchEvents)
        XCTAssertEqual(searchPayload?["status"], "completed")
        XCTAssertTrue((searchPayload?["output"] ?? "").contains("LazyIndexSymbol"))

        let after = await runtime.debugSnapshot()
        XCTAssertTrue(after.hasCodebaseIndex)
    }

    func testSemanticSearchNoResultsReturnsEmpty() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a file with unrelated content
        let file = tmp.appendingPathComponent("hello.txt")
        try "this is just a plain text file".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "xyzzyNonexistentSymbol12345"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["count"], "0")
    }

    func testSemanticSearchEventType() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "anything"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        let hasCorrectType = events.contains { event in
            if case .raw(let type, _) = event {
                return type == "read_batch_completed"
            }
            return false
        }
        XCTAssertTrue(hasCorrectType, "semantic_search should emit read_batch_completed event type")
    }

}
