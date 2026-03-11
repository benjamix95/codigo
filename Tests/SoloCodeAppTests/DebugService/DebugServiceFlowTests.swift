import XCTest
@testable import CoderIDE

final class DebugServiceFlowTests: XCTestCase {
    func testFlowStartStepRefreshStopMantieneOrdineEStatoAtteso() async {
        let adapter = RecordingNativeDebugAdapter()
        let service = DebugService(adapter: adapter)
        let coordinator = DebugExecutionCoordinator(service: service)

        let start = await coordinator.execute(
            .start(
                targetPath: "/tmp/bin/demo-app",
                arguments: ["--dry-run"],
                breakpoints: [DebugBreakpoint(filePath: "Sources/Main.swift", line: 33)],
                watchExpressions: ["state.phase"]
            )
        )
        XCTAssertEqual(start.status, .running)
        XCTAssertEqual(start.lastCommand, "start")
        XCTAssertEqual(start.metrics.totalOperations, 1)
        XCTAssertEqual(start.metrics.lastStage?.stage, .start)

        let step = await coordinator.execute(.stepOver)
        XCTAssertEqual(step.status, .paused)
        XCTAssertEqual(step.lastCommand, "thread step-over")
        XCTAssertEqual(step.metrics.totalOperations, 2)
        XCTAssertEqual(step.metrics.lastStage?.stage, .stepOver)

        let refresh = await coordinator.execute(.refresh)
        XCTAssertEqual(refresh.status, .paused)
        XCTAssertEqual(refresh.lastCommand, "refresh")
        XCTAssertEqual(refresh.metrics.totalOperations, 3)
        XCTAssertEqual(refresh.metrics.lastStage?.stage, .refresh)

        let stop = await coordinator.execute(.stop)
        XCTAssertEqual(stop.status, .stopped)
        XCTAssertEqual(stop.lastCommand, "stop")
        XCTAssertEqual(stop.metrics.totalOperations, 4)
        XCTAssertEqual(stop.metrics.lastStage?.stage, .stop)

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

    func testServiceDisabilitatoDaFeatureFlagUsaFallbackSafe() async {
        let service = DebugService(configuration: DebugServiceConfiguration(
            debugServiceEnabled: false,
            debugDAPLLDBEnabled: true
        ))

        let state = await service.startSession(
            targetPath: "/bin/ls",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.adapter, "native-debug-disabled")
        XCTAssertTrue(state.lastError?.contains("debug_service_enabled") ?? false)
    }

    func testServiceRecoversAfterAdapterErrorWhenRecoveryEnabled() async {
        let counter = RecoveryFactoryCounter()
        let initialAdapter = FlakyNativeDebugAdapter()
        let recovery = DebugAdapterRecovery(
            adapter: initialAdapter,
            adapterFactory: {
                counter.increment()
                return RecordingNativeDebugAdapter(name: "recovered-adapter")
            }
        )
        let service = DebugService(adapter: initialAdapter, recovery: recovery)

        let state = await service.startSession(
            targetPath: "/tmp/bin/demo-app",
            arguments: [],
            breakpoints: [],
            watchExpressions: []
        )

        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.adapter, "recovered-adapter")
        XCTAssertEqual(counter.value, 1)
    }
}

private final class RecoveryFactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private actor FlakyNativeDebugAdapter: NativeDebugAdapter {
    nonisolated let name = "flaky-adapter"
    private var hasFailed = false

    func startSession(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    ) async -> NativeDebugSessionState {
        guard !hasFailed else {
            return NativeDebugSessionState(
                status: .running,
                adapter: name,
                targetPath: targetPath,
                breakpointsCount: breakpoints.count,
                callStack: [],
                watchVariables: watchExpressions.map { NativeWatchVariable(expression: $0, value: "ok") },
                lastCommand: "start",
                lastError: nil,
                updatedAt: Date()
            )
        }

        hasFailed = true
        return NativeDebugSessionState(
            status: .error,
            adapter: name,
            targetPath: targetPath,
            breakpointsCount: breakpoints.count,
            callStack: [],
            watchVariables: [],
            lastCommand: "start",
            lastError: "simulated adapter failure",
            updatedAt: Date()
        )
    }

    func syncBreakpoints(_ breakpoints: [DebugBreakpoint]) async -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .running,
            adapter: name,
            targetPath: nil,
            breakpointsCount: breakpoints.count,
            callStack: [],
            watchVariables: [],
            lastCommand: "sync_breakpoints",
            lastError: nil,
            updatedAt: Date()
        )
    }

    func syncWatches(_ expressions: [String]) async -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .running,
            adapter: name,
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: expressions.map { NativeWatchVariable(expression: $0, value: "ok") },
            lastCommand: "sync_watches",
            lastError: nil,
            updatedAt: Date()
        )
    }

    func step(command: String) async -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .paused,
            adapter: name,
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: [],
            lastCommand: command,
            lastError: nil,
            updatedAt: Date()
        )
    }

    func refresh() async -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .paused,
            adapter: name,
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: [],
            lastCommand: "refresh",
            lastError: nil,
            updatedAt: Date()
        )
    }

    func stopSession() async -> NativeDebugSessionState {
        NativeDebugSessionState(
            status: .stopped,
            adapter: name,
            targetPath: nil,
            breakpointsCount: 0,
            callStack: [],
            watchVariables: [],
            lastCommand: "stop",
            lastError: nil,
            updatedAt: Date()
        )
    }
}
