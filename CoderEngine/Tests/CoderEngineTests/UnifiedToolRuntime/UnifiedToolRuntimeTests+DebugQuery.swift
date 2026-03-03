import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
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
        await runtime.debugLogServer.clear()
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

    func testDebugQueryHypothesisFilterUsesStructuredHypothesisField() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hypothesisId = UUID().uuidString
        let (logCall, logCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Compiler",
                "message": "Type mismatch",
                "category": "compiler",
                "hypothesis_id": hypothesisId
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logCall, context: logCtx)

        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: [
                "format": "full",
                "hypothesis_id": hypothesisId
            ],
            workspace: tmp
        )
        let events = await runtime.execute(queryCall, context: queryCtx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("Type mismatch"))
    }

    func testDebugQueryReturnsMostRecentEntriesFirst() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (firstLog, firstCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "older-entry"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(firstLog, context: firstCtx)

        let (secondLog, secondCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "newer-entry"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(secondLog, context: secondCtx)

        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: [
                "format": "full",
                "limit": "1"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(queryCall, context: queryCtx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertTrue(output.contains("newer-entry"))
        XCTAssertFalse(output.contains("older-entry"))
    }

    func testDebugQueryTagsFilterMatchesExactTags() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (logCall, logCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "Tagged event",
                "tags": "error"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logCall, context: logCtx)

        let (queryCall, queryCtx) = makeCall(
            name: "debug_query",
            args: [
                "format": "summary",
                "tags": "or"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(queryCall, context: queryCtx)
        let completed = extractLastPayload(events)
        let output = completed?["output"] ?? ""

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue(output.contains("Total entries: 0"))
    }

    func testDebugLogEmitsDedicatedEventType() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (call, ctx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "Boot"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)

        XCTAssertTrue(events.contains { event in
            if case .raw(let type, _) = event {
                return type == "debug_log"
            }
            return false
        })
    }
}
