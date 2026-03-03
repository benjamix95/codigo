import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
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
}
