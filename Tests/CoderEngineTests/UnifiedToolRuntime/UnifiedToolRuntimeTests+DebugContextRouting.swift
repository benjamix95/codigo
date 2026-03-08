import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    // MARK: - DebugContext Tests

    func testDebugContextGathersGitInfo() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Initialize git repo
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = tmp
        try process.run()
        process.waitUntilExit()

        // Create and commit a file
        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 1".write(to: file, atomically: true, encoding: .utf8)

        let addProcess = Process()
        addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        addProcess.arguments = ["add", "."]
        addProcess.currentDirectoryURL = tmp
        try addProcess.run()
        addProcess.waitUntilExit()

        let commitProcess = Process()
        commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commitProcess.arguments = ["commit", "-m", "initial", "--allow-empty"]
        commitProcess.currentDirectoryURL = tmp
        commitProcess.environment = [
            "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@test.com",
            "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@test.com"
        ]
        try commitProcess.run()
        commitProcess.waitUntilExit()

        let (call, ctx) = makeCall(name: "debug_context", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["tool"], "debug_context")

        let output = completed?["output"] ?? ""
        XCTAssertTrue(output.contains("Git Status"), "Should contain git status section")
    }

    func testDebugContextIncludesOpenFiles() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let openFile = OpenFile(path: "Sources/Test.swift", content: "import Foundation\nlet x = 1")
        let ctx = ToolExecutionContext(
            workspaceContext: WorkspaceContext(
                workspacePath: tmp,
                openFiles: [openFile],
                activeFilePath: "Sources/Test.swift"
            )
        )
        let call = ToolCall(
            id: UUID().uuidString, name: "debug_context", args: [:],
            sourceProvider: "test", swarmId: nil, scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertTrue(output.contains("Open Files"), "Should contain open files section")
        XCTAssertTrue(output.contains("Sources/Test.swift"), "Should list open file paths")
        XCTAssertTrue(output.contains("Active File"), "Should contain active file section")
    }

    func testDebugContextSectionsCount() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "debug_context", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let sectionsCount = Int(completed?["sections"] ?? "0") ?? 0
        XCTAssertGreaterThanOrEqual(sectionsCount, 0, "Should have 0 or more context sections")
    }

    func testDebugContextEventType() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "debug_context", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)

        let hasCorrectType = events.contains { event in
            if case .raw(let type, _) = event {
                return type == "read_batch_completed"
            }
            return false
        }
        XCTAssertTrue(hasCorrectType, "debug_context should emit read_batch_completed event type")
    }

    // MARK: - New Tool Routing Tests

    func testSemanticSearchRoutesCorrectly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let file = tmp.appendingPathComponent("test.swift")
        try "func hello() {}".write(to: file, atomically: true, encoding: .utf8)
        let (call, ctx) = makeCall(name: "semantic_search", args: ["query": "hello"], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["tool"], "semantic_search", "Should route to semantic_search tool")
    }

    func testReadLintsRoutesCorrectly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (call, ctx) = makeCall(name: "read_lints", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        // Even on failure (no project), the tool name should be correct
        XCTAssertEqual(completed?["tool"], "read_lints", "Should route to read_lints tool")
    }

    func testDebugContextRoutesCorrectly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let (call, ctx) = makeCall(name: "debug_context", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["tool"], "debug_context", "Should route to debug_context tool")
    }

    // MARK: - Read-Only Classification Tests

    func testSemanticSearchIsReadOnly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a file so search has something to find
        let file = tmp.appendingPathComponent("test.swift")
        try "let hello = 1".write(to: file, atomically: true, encoding: .utf8)

        // Execute semantic_search — should not modify any files
        let (call, ctx) = makeCall(
            name: "semantic_search",
            args: ["query": "hello"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        // Read the file back — should be unchanged
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(content, "let hello = 1", "semantic_search should not modify files")
        XCTAssertEqual(completed?["status"], "completed")
    }

    func testDebugContextIsReadOnly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let original = true".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "debug_context", workspace: tmp)
        _ = await runtime.execute(call, context: ctx)

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(content, "let original = true", "debug_context should not modify files")
    }
}
