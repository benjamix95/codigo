import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
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

}
