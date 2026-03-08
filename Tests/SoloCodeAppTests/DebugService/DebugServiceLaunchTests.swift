import XCTest
@testable import CoderIDE

final class DebugServiceLaunchTests: XCTestCase {
    func testStartSessionPropagaTargetArgsBreakpointsEWatchesAlLaunchAdapter() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        var secondBreakpoint = DebugBreakpoint(
            filePath: "Sources/App.swift",
            line: 20,
            condition: "counter > 10"
        )
        secondBreakpoint.isActive = false

        let state = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: ["--mode", "integration", "--verbose"],
            breakpoints: [
                DebugBreakpoint(filePath: "Sources/App.swift", line: 10),
                secondBreakpoint
            ],
            watchExpressions: ["counter", "user.id"]
        )

        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.adapter, "mock-recorder")
        XCTAssertEqual(state.targetPath, "/tmp/bin/demo-app")

        let starts = await adapter.recordedStarts()
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts.first?.targetPath, "/tmp/bin/demo-app")
        XCTAssertEqual(starts.first?.arguments, ["--mode", "integration", "--verbose"])
        XCTAssertEqual(starts.first?.breakpoints.count, 2)
        XCTAssertEqual(starts.first?.watchExpressions, ["counter", "user.id"])
    }

    func testStepInInviaComandoEffettivoAllAdapter() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        _ = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let stepState = await service.stepIn()

        XCTAssertEqual(stepState.status, .paused)
        XCTAssertEqual(stepState.lastCommand, "thread step-in")

        let events = await adapter.recordedEvents()
        XCTAssertEqual(events, [.start(arguments: []), .step(command: "thread step-in")])
    }
}
