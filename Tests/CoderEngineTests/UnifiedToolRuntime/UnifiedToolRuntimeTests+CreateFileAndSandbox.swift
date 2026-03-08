import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
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

    func testSandboxBlocksReadViaSymlinkEscape() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let outsideDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }

        let outsideFile = outsideDir.appendingPathComponent("secret.txt")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)

        let symlinkPath = tmp.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: outsideDir)

        let (call, ctx) = makeCall(name: "read", args: ["path": "escape/secret.txt"], workspace: tmp)
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "sandbox_violation")
    }

}
