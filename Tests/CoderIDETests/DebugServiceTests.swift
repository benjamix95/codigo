import XCTest
@testable import CoderIDE

final class DebugServiceTests: XCTestCase {
    func testDebugServiceStartAndSnapshot() async {
        let adapter = MockNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        let state = await service.startSession(
            targetPath: "/tmp/fake-binary",
            arguments: [],
            breakpoints: [],
            watchExpressions: ["counter"]
        )

        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.adapter, "mock")
        XCTAssertEqual(state.targetPath, "/tmp/fake-binary")

        let snapshot = await service.snapshot()
        XCTAssertEqual(snapshot.status, .running)
    }

    func testDebugServiceStepAndSyncOperations() async {
        let adapter = MockNativeDebugAdapter()
        let service = DebugService(adapter: adapter)

        _ = await service.startSession(
            targetPath: "/tmp/fake-binary",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        let stepState = await service.stepIn()
        XCTAssertEqual(stepState.lastCommand, "thread step-in")

        let stepOverState = await service.stepOver()
        XCTAssertEqual(stepOverState.lastCommand, "thread step-over")

        let syncWatchState = await service.syncWatches(["value", "count"])
        XCTAssertEqual(syncWatchState.watchVariables.count, 2)

        let bp = DebugBreakpoint(filePath: "Sources/Foo.swift", line: 42, condition: "value > 0")
        let syncBpState = await service.syncBreakpoints([bp])
        XCTAssertEqual(syncBpState.breakpointsCount, 1)

        let stopState = await service.stopSession()
        XCTAssertEqual(stopState.status, .stopped)
    }
}

private actor MockNativeDebugAdapter: NativeDebugAdapter {
    nonisolated let name = "mock"
    private var state = NativeDebugSessionState.idle

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        state = NativeDebugSessionState(
            status: .running,
            adapter: name,
            targetPath: targetPath,
            breakpointsCount: breakpoints.count,
            callStack: [],
            watchVariables: watchExpressions.map { NativeWatchVariable(expression: $0, value: "n/a") },
            lastCommand: "start",
            lastError: nil,
            updatedAt: Date()
        )
        return state
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        state.breakpointsCount = breakpoints.count
        state.lastCommand = "sync_breakpoints"
        state.updatedAt = Date()
        return state
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        state.watchVariables = expressions.map { NativeWatchVariable(expression: $0, value: "mock") }
        state.lastCommand = "sync_watches"
        state.updatedAt = Date()
        return state
    }

    func step(command: String) async -> NativeDebugSessionState {
        state.status = .paused
        state.lastCommand = command
        state.updatedAt = Date()
        return state
    }

    func refresh() async -> NativeDebugSessionState {
        state.lastCommand = "refresh"
        state.updatedAt = Date()
        return state
    }

    func stopSession() async -> NativeDebugSessionState {
        state.status = .stopped
        state.lastCommand = "stop"
        state.updatedAt = Date()
        return state
    }
}
