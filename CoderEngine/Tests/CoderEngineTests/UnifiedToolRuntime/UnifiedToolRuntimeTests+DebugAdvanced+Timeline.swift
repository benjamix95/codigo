import XCTest
@testable import CoderEngine

extension UnifiedToolRuntimeTests {
    func testDebugInstrumentRejectsUnknownType() async throws {
        let runtime = UnifiedToolRuntime()
        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let file = tmp.appendingPathComponent("instrument.swift")
        try "let a = 1\nlet b = 2".write(to: file, atomically: true, encoding: .utf8)

        let (call, ctx) = makeCall(
            name: "debug_instrument",
            args: [
                "path": file.path,
                "line": "1",
                "type": "unknown_type",
                "expression": "a"
            ],
            workspace: tmp
        )
        let events = await runtime.execute(call, context: ctx)
        let payload = extractLastPayload(events)

        XCTAssertEqual(payload?["status"], "failed")
        XCTAssertTrue((payload?["detail"] ?? "").contains("Unknown instrumentation type"))
    }

    func testDebugLogBatchPreservesTagsAndStackTrace() async throws {
        let runtime = UnifiedToolRuntime()
        await runtime.debugLogServer.clear()

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let batch = """
        [{"severity":"error","source":"Runtime","message":"batch-event","tags":"network,timeout","stack_trace":"frame1\\nframe2","category":"runtime","data":{"attempt":"1"}}]
        """
        let (batchCall, batchCtx) = makeCall(
            name: "debug_log",
            args: ["batch": batch],
            workspace: tmp
        )
        _ = await runtime.execute(batchCall, context: batchCtx)

        let (query, queryCtx) = makeCall(
            name: "debug_query",
            args: ["format": "full", "tags": "timeout"],
            workspace: tmp
        )
        let queryEvents = await runtime.execute(query, context: queryCtx)
        let queryPayload = extractLastPayload(queryEvents)
        let output = queryPayload?["output"] ?? ""

        XCTAssertEqual(queryPayload?["status"], "completed")
        XCTAssertTrue(output.contains("batch-event"))
        XCTAssertTrue(output.contains("Stack Trace"))
    }

    func testDebugTimelineShortHypothesisFilterMatchesLogsAndHypothesisEvents() async throws {
        let runtime = UnifiedToolRuntime()
        await runtime.debugLogServer.clear()

        let tmp = try makeTmpWorkspace()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (propose, proposeCtx) = makeCall(
            name: "debug_hypothesize",
            args: [
                "action": "propose",
                "title": "Timeline filter check",
                "description": "Ensure short hypothesis id filters consistently"
            ],
            workspace: tmp
        )
        let proposeEvents = await runtime.execute(propose, context: proposeCtx)
        let proposePayload = extractLastPayload(proposeEvents)
        let hypothesisID = proposePayload?["hypothesis_id"] ?? ""
        XCTAssertFalse(hypothesisID.isEmpty)
        let shortID = String(hypothesisID.prefix(8))

        let (logRelated, logRelatedCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "timeline-related-entry",
                "hypothesis_id": hypothesisID
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logRelated, context: logRelatedCtx)

        let (logOther, logOtherCtx) = makeCall(
            name: "debug_log",
            args: [
                "severity": "info",
                "source": "Runtime",
                "message": "timeline-unrelated-entry"
            ],
            workspace: tmp
        )
        _ = await runtime.execute(logOther, context: logOtherCtx)

        let (timeline, timelineCtx) = makeCall(
            name: "debug_timeline",
            args: [
                "filter": "logs,hypotheses",
                "hypothesis_id": shortID,
                "format": "text"
            ],
            workspace: tmp
        )
        let timelineEvents = await runtime.execute(timeline, context: timelineCtx)
        let timelinePayload = extractLastPayload(timelineEvents)
        let output = timelinePayload?["output"] ?? ""

        XCTAssertEqual(timelinePayload?["status"], "completed")
        XCTAssertTrue(output.contains("timeline-related-entry"))
        XCTAssertTrue(output.contains(shortID))
        XCTAssertFalse(output.contains("timeline-unrelated-entry"))
    }
}
