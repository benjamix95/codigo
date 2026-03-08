import XCTest
@testable import CoderIDE

final class DebugServiceSyncTests: XCTestCase {
    func testSyncBreakpointsAggiornaLoStatoSessione() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        _ = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let first = DebugBreakpoint(filePath: "Sources/A.swift", line: 7)
        let second = DebugBreakpoint(filePath: "Sources/B.swift", line: 8, condition: "x > 0")
        let syncState = await service.syncBreakpoints([first, second])

        XCTAssertEqual(syncState.lastCommand, "sync_breakpoints")
        XCTAssertEqual(syncState.breakpointsCount, 2)

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.breakpointsCount, 2)
    }

    func testSyncWatchesAggiornaLoStatoSessioneConValoriDeterministici() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        _ = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let syncState = await service.syncWatches(["counter", "items.count"])

        XCTAssertEqual(syncState.lastCommand, "sync_watches")
        XCTAssertEqual(syncState.watchVariables.count, 2)
        XCTAssertEqual(syncState.watchVariables[0].expression, "counter")
        XCTAssertEqual(syncState.watchVariables[0].value, "value-0")
        XCTAssertEqual(syncState.watchVariables[1].expression, "items.count")
        XCTAssertEqual(syncState.watchVariables[1].value, "value-1")

        let events = await adapter.recordedEvents()
        XCTAssertEqual(
            events,
            [
                .start(arguments: []),
                .syncWatches(expressions: ["counter", "items.count"])
            ]
        )
    }
}
