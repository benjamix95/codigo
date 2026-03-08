import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testDebugCleanDryRunPreservesPreviewStatus() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("sample.swift")
        try """
        print("hello")
        // 🐛 DEBUG: trace
        """.write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "debug_clean",
            args: [
                "path": file.path,
                "dry_run": "true"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "preview")
        XCTAssertEqual(completed?["dry_run"], "true")
    }

    func testDebugCleanTypedLogsRemovesInstrumentLogMarkers() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("sample.swift")
        try """
        let value = 1
        print(value) // 🐛 DEBUG[instrument-log]: value
        assert(value > 0) // 🐛 DEBUG[instrument-assert]: value positive
        """.write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "debug_clean",
            args: [
                "path": file.path,
                "type": "logs",
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertFalse(content.contains("DEBUG[instrument-log]"))
        XCTAssertTrue(content.contains("DEBUG[instrument-assert]"))
    }

    func testDebugCleanWithoutPathScansWorkspace() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let nestedDir = tmp.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let file = nestedDir.appendingPathComponent("feature.swift")
        try """
        let value = 1
        // 🐛 DEBUG[marker]: cleanup me
        """.write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "debug_clean",
            args: ["type": "markers"],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "completed")
        XCTAssertEqual(payload?["cleaned_markers"], "1")
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(content.contains("DEBUG[marker]"))
    }

    func testDebugSessionEndSummaryUsesCurrentSessionOnly() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (startA, startCtxA) = makeCall(name: "debug_session", args: ["action": "start"], workspace: tmp)
        _ = await runtime.execute(startA, context: startCtxA)

        let (logA, logCtxA) = makeCall(
            name: "debug_log",
            args: [
                "severity": "error",
                "source": "SessionA",
                "message": "session-a-error",
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logA, context: logCtxA)

        let (endA, endCtxA) = makeCall(name: "debug_session", args: ["action": "end"], workspace: tmp)
        _ = await runtime.execute(endA, context: endCtxA)

        let (startB, startCtxB) = makeCall(name: "debug_session", args: ["action": "start"], workspace: tmp)
        _ = await runtime.execute(startB, context: startCtxB)

        let (endB, endCtxB) = makeCall(name: "debug_session", args: ["action": "end"], workspace: tmp)
        let endBEvents = await runtime.execute(endB, context: endCtxB)
        let endBPayload = extractLastPayload(endBEvents)
        let output = endBPayload?["output"] ?? ""

        XCTAssertEqual(endBPayload?["status"], "completed")
        XCTAssertTrue(output.contains("Errors: 0"))
        XCTAssertFalse(output.contains("session-a-error"))
    }

    func testDebugLogServerLoadsFromDiskForNewRuntimeInstance() async throws {
        let runtimeA = UnifiedToolRuntime()
        await runtimeA.debugLogServer.clear()

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let uniqueMessage = "persist-\(UUID().uuidString)"
        let (logCall, logCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Persistence",
                "message": uniqueMessage,
            ],
            workspace: tmp
        )
        _ = await runtimeA.execute(logCall, context: logCtx)

        let runtimeB = UnifiedToolRuntime()
        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: [
                "format": "full",
                "search": uniqueMessage,
            ],
            workspace: tmp
        )
        let queryEvents = await runtimeB.execute(queryCall, context: queryCtx)
        let queryPayload = extractLastPayload(queryEvents)

        XCTAssertEqual(queryPayload?["status"], "completed")
        XCTAssertTrue((queryPayload?["output"] ?? "").contains(uniqueMessage))
        await runtimeA.debugLogServer.clear()
        await runtimeB.debugLogServer.clear()
    }

}
