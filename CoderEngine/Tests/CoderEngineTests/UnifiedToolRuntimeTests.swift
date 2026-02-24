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
}
