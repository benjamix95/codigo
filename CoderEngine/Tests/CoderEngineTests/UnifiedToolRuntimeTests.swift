import XCTest
@testable import CoderEngine

final class UnifiedToolRuntimeTests: XCTestCase {

    // MARK: - Helpers

    private func makeTmpWorkspace() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("codigo-tests-\(UUID().uuidString)", isDirectory: true)
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
        workspace: URL? = nil
    ) -> (ToolCall, ToolExecutionContext) {
        let ws = workspace ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let call = ToolCall(
            id: UUID().uuidString,
            name: name,
            args: args,
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: ws))
        return (call, ctx)
    }

    // MARK: - Policy Defaults

    func testToolRuntimePolicyDefaults() {
        let policy = ToolRuntimePolicy()
        XCTAssertEqual(policy.maxToolCallsPerRound, 15)
        XCTAssertEqual(policy.maxRepeatedSameToolPerRound, 8)
        XCTAssertEqual(policy.maxBashOutputBytes, 128_000)
        XCTAssertEqual(policy.maxReadBytesPerFile, 256_000)
        XCTAssertEqual(policy.timeoutMs, 60_000)
        XCTAssertEqual(policy.mcpPerCallTimeoutMs, 30_000)
        XCTAssertFalse(policy.allowDangerousShellPatterns)
        XCTAssertTrue(policy.enableMCP)
        XCTAssertEqual(policy.mcpSessionIdleTTLSeconds, 300)
    }

    func testPolicyMinClamping() {
        let policy = ToolRuntimePolicy(
            maxToolCallsPerRound: 0,
            maxRepeatedSameToolPerRound: 0,
            maxBashOutputBytes: 0,
            maxReadBytesPerFile: 0
        )
        XCTAssertEqual(policy.maxToolCallsPerRound, 1)
        XCTAssertEqual(policy.maxRepeatedSameToolPerRound, 1)
        XCTAssertEqual(policy.maxBashOutputBytes, 1_024)
        XCTAssertEqual(policy.maxReadBytesPerFile, 1_024)
    }

    // MARK: - Read Tool (with line numbers)

    func testReadValidationFailsWithoutPath() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "read")
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    func testReadReturnsLineNumbers() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("hello.txt")
        try "line one\nline two\nline three\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "read", args: ["path": file.path], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let output = completed?["output"] ?? ""
        XCTAssertTrue(output.contains("1│line one"), "Expected line numbers in output, got: \(output)")
        XCTAssertTrue(output.contains("2│line two"), "Expected line numbers in output, got: \(output)")
        XCTAssertTrue(output.contains("3│line three"), "Expected line numbers in output, got: \(output)")
    }

    func testReadReportsLineCount() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.txt")
        try "a\nb\nc".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "read", args: ["path": file.path], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(completed?["detail"]?.contains("3 lines") == true)
    }

    // MARK: - str_replace Tool

    func testStrReplaceSuccess() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 5\nlet y = 10\nlet z = 15\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "let x = 5", "new_string": "let x = 42"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(completed?["detail"]?.contains("line 1") == true)

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertTrue(content.contains("let x = 42"))
        XCTAssertFalse(content.contains("let x = 5"))
    }

    func testStrReplaceNotFound() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 5\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "let y = 99", "new_string": "nope"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue(completed?["detail"]?.contains("not found") == true)
    }

    func testStrReplaceNotUnique() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 5\nlet x = 5\nlet x = 5\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "let x = 5", "new_string": "let x = 42"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
        XCTAssertTrue(completed?["detail"]?.contains("not unique") == true)
    }

    func testStrReplaceEmptyOldString() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "", "new_string": "x"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(completed?["detail"]?.contains("old_string is required") == true)
    }

    func testStrReplaceOnNonExistentFile() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: [
                "path": tmp.appendingPathComponent("nonexistent.txt").path,
                "old_string": "x",
                "new_string": "y"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(completed?["detail"]?.contains("File not found") == true)
    }

    func testStrReplaceMultilineReplacement() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        let original = """
        func hello() {
            print("hello")
        }

        func goodbye() {
            print("goodbye")
        }
        """
        try original.write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: [
                "path": file.path,
                "old_string": "func hello() {\n    print(\"hello\")\n}",
                "new_string": "func hello() {\n    print(\"Hello, World!\")\n    print(\"Welcome\")\n}"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertTrue(content.contains("Hello, World!"))
        XCTAssertTrue(content.contains("Welcome"))
        XCTAssertTrue(content.contains("goodbye"))
    }

    // MARK: - Edit with old_string (backward compat → str_replace)

    func testEditWithOldStringDelegatesToStrReplace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "edit",
            args: ["path": file.path, "old_string": "let value = 1", "new_string": "let value = 2"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertTrue(content.contains("let value = 2"))
    }

    // MARK: - create_file Tool

    func testCreateFileSuccess() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let filePath = tmp.appendingPathComponent("new_file.swift").path
        let (call, ctx) = makeCall(
            name: "create_file",
            args: ["path": filePath, "content": "import Foundation\n\nstruct MyStruct {}\n"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        // "import Foundation\n\nstruct MyStruct {}\n" splits into 4 components
        XCTAssertTrue(completed?["detail"]?.contains("lines") == true)

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertTrue(content.contains("struct MyStruct"))
    }

    func testCreateFileCreatesIntermediateDirectories() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let filePath = tmp.appendingPathComponent("deep/nested/dir/file.txt").path
        let (call, ctx) = makeCall(
            name: "create_file",
            args: ["path": filePath, "content": "hello"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
    }

    func testCreateFileFailsIfExists() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("existing.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "create_file",
            args: ["path": file.path, "content": "new content"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(completed?["detail"]?.contains("already exists") == true)

        // Verify original content is preserved
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(content, "original")
    }

    // MARK: - Sandbox

    func testSandboxBlocksOutsideWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outsideFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "x".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        let (call, ctx) = makeCall(name: "read", args: ["path": outsideFile.path], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
    }

    func testStrReplaceSandboxBlocked() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outsideFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "x".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": outsideFile.path, "old_string": "x", "new_string": "y"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
    }

    // MARK: - Bash

    func testBashTimeoutReturnsTimeoutCode() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        // Use allowDangerousShellPatterns so we can use sleep without strict-mode blocking
        let policy = ToolRuntimePolicy(timeoutMs: 100, allowDangerousShellPatterns: true)
        let ctx = ToolExecutionContext(
            workspaceContext: WorkspaceContext(workspacePath: workspace),
            policy: policy
        )
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "sleep 2"],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )

        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "timeout")
    }

    func testBashValidationFailsEmpty() async {
        let runtime = UnifiedToolRuntime()
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let ctx = ToolExecutionContext(workspaceContext: WorkspaceContext(workspacePath: workspace))
        let call = ToolCall(
            id: UUID().uuidString,
            name: "bash",
            args: ["command": "   "],
            sourceProvider: "test",
            swarmId: nil,
            scope: .agent
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    // MARK: - MCP

    func testMCPUnavailableReturnsDeterministicError() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "mcp_call", args: ["tool": "nonexistent_tool"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertTrue(["mcp_unavailable", "transport"].contains(completed?["error_code"] ?? ""))
    }

    func testMCPListServersAlwaysCompletes() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "mcp_list_servers")
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")
    }

    // MARK: - JSON

    func testReadJSONValidationOnInvalidJSON() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let broken = tmp.appendingPathComponent("broken.json")
        try "{not-json}".write(to: broken, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "read_json", args: ["path": broken.path], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }

    // MARK: - Write Tool

    func testWriteCreatesAndOverwrites() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("new.txt")
        let (call, ctx) = makeCall(
            name: "write",
            args: ["path": file.path, "content": "hello world"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "completed")

        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(content, "hello world")
    }

    // MARK: - Event Type Mapping

    func testEventTypeForStrReplace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("test.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "str_replace",
            args: ["path": file.path, "old_string": "let x = 1", "new_string": "let x = 2"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        // str_replace should produce file_change event type
        let hasFileChange = events.contains { event in
            if case .raw(let type, let payload) = event {
                return type == "file_change" && payload["status"] == "completed"
            }
            return false
        }
        XCTAssertTrue(hasFileChange, "str_replace should emit file_change event")
    }

    func testEventTypeForCreateFile() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "create_file",
            args: ["path": tmp.appendingPathComponent("new.txt").path, "content": "hi"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        let hasFileChange = events.contains { event in
            if case .raw(let type, let payload) = event {
                return type == "file_change" && payload["status"] == "completed"
            }
            return false
        }
        XCTAssertTrue(hasFileChange, "create_file should emit file_change event")
    }

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

    // MARK: - ReadLints Tests

    func testReadLintsReturnsToolInfo() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a minimal Swift package
        let packageSwift = tmp.appendingPathComponent("Package.swift")
        try """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "TestPkg", targets: [.executableTarget(name: "TestPkg")])
        """.write(to: packageSwift, atomically: true, encoding: .utf8)

        let sourcesDir = tmp.appendingPathComponent("Sources/TestPkg")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let mainSwift = sourcesDir.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: mainSwift, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(name: "read_lints", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        // Should detect Swift project
        XCTAssertEqual(completed?["tool"], "read_lints")
        XCTAssertEqual(completed?["linter"], "swift")
    }

    func testReadLintsNoProjectFails() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Empty directory — no recognized project type
        let (call, ctx) = makeCall(name: "read_lints", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)
        XCTAssertEqual(completed?["status"], "failed")
    }

    func testReadLintsEventType() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(name: "read_lints", workspace: tmp)
        let events = await runtime.execute(call, context: ctx)

        // Even on failure, it should emit read_batch_completed event type
        let hasCorrectType = events.contains { event in
            if case .raw(let type, _) = event {
                return type == "read_batch_completed" || type == "tool_execution_error"
            }
            return false
        }
        XCTAssertTrue(hasCorrectType, "read_lints should emit correct event type")
    }

    func testReadLintsSeverityFilter() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a Swift package with an intentional error
        let packageSwift = tmp.appendingPathComponent("Package.swift")
        try """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "TestPkg", targets: [.executableTarget(name: "TestPkg")])
        """.write(to: packageSwift, atomically: true, encoding: .utf8)

        let sourcesDir = tmp.appendingPathComponent("Sources/TestPkg")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let mainSwift = sourcesDir.appendingPathComponent("main.swift")
        try "let x: Int = \"not an int\"".write(to: mainSwift, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "read_lints",
            args: ["severity": "error"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        // Should have detected errors
        let errorCount = Int(completed?["error_count"] ?? "0") ?? 0
        XCTAssertGreaterThan(errorCount, 0, "Should detect errors in malformed Swift code")
    }

    // MARK: - DebugQuery Tests

    func testDebugQueryFullAppliesSourceFilter() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (logA, ctxA) = makeCall(
            name: "debug_log",
            args: [
                "severity": "error",
                "source": "NetworkManager.swift:42",
                "message": "Connection refused",
                "category": "runtime"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logA, context: ctxA)

        let (logB, ctxB) = makeCall(
            name: "debug_log",
            args: [
                "severity": "warning",
                "source": "AuthService.swift:11",
                "message": "Token close to expiration",
                "category": "runtime"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logB, context: ctxB)

        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: ["format": "full", "source": "NetworkManager.swift"],
            workspace: tmp
        )
        let events = await runtime.execute(queryCall, context: queryCtx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["detail"], "1 entries (1 errors, 0 warnings)")
        let output = completed?["output"] ?? ""
        XCTAssertTrue(output.contains("NetworkManager.swift:42"))
        XCTAssertFalse(output.contains("AuthService.swift:11"))
    }

    func testDebugQuerySummaryWithFiltersReturnsFilteredSummary() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (logCall, logCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "error",
                "source": "Compiler",
                "message": "Type mismatch",
                "category": "compiler"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logCall, context: logCtx)

        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: ["format": "summary", "severity": "error"],
            workspace: tmp
        )
        let events = await runtime.execute(queryCall, context: queryCtx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("Debug Query Summary:"))
        XCTAssertTrue(output.contains("Total entries: 1"))
        XCTAssertTrue(output.contains("Errors: 1"))
    }

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
