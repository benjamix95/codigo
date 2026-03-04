import XCTest
@testable import CoderIDE

final class DebugServiceFlowTests: XCTestCase {
    func testFlowStartStepRefreshStopMantieneOrdineEStatoAtteso() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        let start = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: ["--dry-run"],
            breakpoints: [DebugBreakpoint(filePath: "Sources/Main.swift", line: 33)],
            watchExpressions: ["state.phase"]
        )
        XCTAssertEqual(start.status, .running)
        XCTAssertEqual(start.lastCommand, "start")

        let step = await service.stepOver()
        XCTAssertEqual(step.status, .paused)
        XCTAssertEqual(step.lastCommand, "thread step-over")

        let refresh = await service.refresh()
        XCTAssertEqual(refresh.status, .paused)
        XCTAssertEqual(refresh.lastCommand, "refresh")

        let stop = await service.stopSession()
        XCTAssertEqual(stop.status, .stopped)
        XCTAssertEqual(stop.lastCommand, "stop")

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.status, .stopped)
        XCTAssertEqual(snapshot.lastCommand, "stop")

        let events = await adapter.recordedEvents()
        XCTAssertEqual(
            events,
            [
                .start(arguments: ["--dry-run"]),
                .step(command: "thread step-over"),
                .refresh,
                .stop
            ]
        )
    }
}
