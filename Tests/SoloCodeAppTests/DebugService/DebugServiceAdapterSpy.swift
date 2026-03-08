import Foundation
@testable import CoderIDE

actor RecordingNativeDebugAdapter: NativeDebugAdapter {
    struct StartCall {
        let targetPath: String
        let arguments: [String]
        let breakpoints: [DebugBreakpoint]
        let watchExpressions: [String]
    }

    enum Event: Equatable {
        case start(arguments: [String])
        case syncBreakpoints(count: Int)
        case syncWatches(expressions: [String])
        case step(command: String)
        case refresh
        case stop
    }

    nonisolated let name: String

    private var now: TimeInterval = 1
    private var state = NativeDebugSessionState.idle
    private var starts: [StartCall] = []
    private var events: [Event] = []

    init(name: String = "mock-recorder") {
        self.name = name
    }

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        starts.append(
            StartCall(
                targetPath: targetPath,
                arguments: arguments,
                breakpoints: breakpoints,
                watchExpressions: watchExpressions
            )
        )
        events.append(.start(arguments: arguments))
        state = NativeDebugSessionState(
            status: .running,
            adapter: name,
            targetPath: targetPath,
            breakpointsCount: breakpoints.count,
            callStack: [],
            watchVariables: watchExpressions.map { NativeWatchVariable(expression: $0, value: "n/a") },
            lastCommand: "start",
            lastError: nil,
            updatedAt: advanceClock()
        )
        return state
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        events.append(.syncBreakpoints(count: breakpoints.count))
        state.breakpointsCount = breakpoints.count
        state.lastCommand = "sync_breakpoints"
        state.updatedAt = advanceClock()
        return state
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        events.append(.syncWatches(expressions: expressions))
        state.watchVariables = expressions.enumerated().map { index, expression in
            NativeWatchVariable(expression: expression, value: "value-\(index)")
        }
        state.lastCommand = "sync_watches"
        state.updatedAt = advanceClock()
        return state
    }

    func step(command: String) async -> NativeDebugSessionState {
        events.append(.step(command: command))
        state.status = .paused
        state.lastCommand = command
        state.updatedAt = advanceClock()
        return state
    }

    func refresh() async -> NativeDebugSessionState {
        events.append(.refresh)
        state.status = .paused
        state.lastCommand = "refresh"
        state.updatedAt = advanceClock()
        return state
    }

    func stopSession() async -> NativeDebugSessionState {
        events.append(.stop)
        state.status = .stopped
        state.lastCommand = "stop"
        state.updatedAt = advanceClock()
        return state
    }

    func recordedStarts() -> [StartCall] {
        starts
    }

    func recordedEvents() -> [Event] {
        events
    }

    private func advanceClock() -> Date {
        defer { now += 1 }
        return Date(timeIntervalSince1970: now)
    }
}
