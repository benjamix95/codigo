import XCTest
@testable import CoderIDE

@MainActor
final class DebugStoreTests: XCTestCase {
    func testStartDebugSessionResetsSessionState() {
        let store = DebugStore()

        store.addLog(severity: .error, source: "runtime", message: "previous")
        _ = store.addHypothesis(title: "old", description: "old")
        store.addBreakpoint(filePath: "A.swift", line: 10)
        store.addRuntimeLog(location: "A.swift:10", message: "old runtime")
        store.addInstrumentation(filePath: "A.swift", lineNumber: 11, type: .logging, code: "print(1)")
        store.addDebugMarker(DebugMarker(filePath: "A.swift", lineNumber: 12, markerComment: "old marker"))
        store.userConfirmedReproduce = true
        store.awaitingDebugClean = true
        store.phase = .fixing
        store.streamingContent = "old stream"
        store.clarificationQuestions = "old question"
        store.resolutionSummary = "old summary"
        store.fixLoopIteration = 3
        store.currentRunId = "old-run"

        store.startDebugSession(errorContext: "new context")

        XCTAssertEqual(store.phase, .describing)
        XCTAssertEqual(store.errorSummary, "new context")
        XCTAssertEqual(store.logs.count, 1)
        XCTAssertEqual(store.logs.first?.message, "Debug session started")
        XCTAssertTrue(store.hypotheses.isEmpty)
        XCTAssertTrue(store.breakpoints.isEmpty)
        XCTAssertTrue(store.runtimeLogs.isEmpty)
        XCTAssertTrue(store.instrumentationPoints.isEmpty)
        XCTAssertTrue(store.debugMarkers.isEmpty)
        XCTAssertFalse(store.userConfirmedReproduce)
        XCTAssertFalse(store.awaitingDebugClean)
        XCTAssertTrue(store.streamingContent.isEmpty)
        XCTAssertTrue(store.clarificationQuestions.isEmpty)
        XCTAssertTrue(store.resolutionSummary.isEmpty)
        XCTAssertEqual(store.fixLoopIteration, 0)
        XCTAssertNil(store.currentRunId)
        XCTAssertEqual(store.debugFlowDiagram, DebugStore.defaultDebugFlowDiagram)
    }

    func testUpdateHypothesisReturnsFalseForUnknownID() {
        let store = DebugStore()
        let updated = store.updateHypothesis(id: UUID(), status: .confirmed, evidence: "no-op")
        XCTAssertFalse(updated)
    }

    func testBeginMarkFixedWaitsForDebugCleanBeforeResolving() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.phase = .verifying
        store.addDebugMarker(DebugMarker(filePath: "A.swift", lineNumber: 12, markerComment: "legacy"))
        store.addInstrumentation(filePath: "A.swift", lineNumber: 14, type: .logging, code: "print(1)")

        let files = store.beginMarkFixed(summary: "Fixed crash")
        XCTAssertTrue(store.awaitingDebugClean)
        XCTAssertEqual(store.phase, .verifying)
        XCTAssertEqual(Set(files), Set(["A.swift"]))

        store.applyDebugCleanResult(success: true, detail: "Removed 2 markers")

        XCTAssertFalse(store.awaitingDebugClean)
        XCTAssertEqual(store.phase, .resolved)
        XCTAssertEqual(store.resolutionSummary, "Fixed crash")
        XCTAssertTrue(store.debugMarkers.isEmpty)
        XCTAssertTrue(store.instrumentationPoints.isEmpty)
    }

    func testCancelPendingMarkFixedRestoresCleanupWaitState() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.phase = .verifying
        _ = store.beginMarkFixed(summary: "Fixed crash")

        store.cancelPendingMarkFixed(reason: "preflight failed")

        XCTAssertFalse(store.awaitingDebugClean)
        XCTAssertNil(store.pendingResolutionAfterClean)
        XCTAssertEqual(store.phase, .verifying)
        XCTAssertEqual(
            store.logs.last?.message,
            "Mark Fixed aborted before cleanup started"
        )
    }

    func testApplyDebugCleanFailureKeepsSessionVerifying() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.phase = .verifying
        _ = store.beginMarkFixed(summary: "Pending cleanup")

        store.applyDebugCleanResult(success: false, detail: "Permission denied")

        XCTAssertFalse(store.awaitingDebugClean)
        XCTAssertEqual(store.phase, .verifying)
        XCTAssertNotEqual(store.resolutionSummary, "Pending cleanup")
    }

    func testInvalidPhaseTransitionIsIgnored() {
        let store = DebugStore()
        XCTAssertEqual(store.phase, .idle)

        store.setPhase(.verifying)

        XCTAssertEqual(store.phase, .idle)
    }

    func testResetSessionRestoresDefaultLogFilters() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.severityFilter = [.error]
        store.categoryFilter = "runtime"
        store.searchQuery = "needle"

        store.resetSession()

        XCTAssertEqual(store.severityFilter, Set(DebugEntrySeverity.allCases))
        XCTAssertNil(store.categoryFilter)
        XCTAssertEqual(store.searchQuery, "")
    }

    func testRuntimeLogUsesExplicitRunIdWhenProvided() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.currentRunId = "current-run"

        store.addRuntimeLog(
            location: "Sources/App.swift:42",
            message: "value=1",
            runId: "incoming-run"
        )

        XCTAssertEqual(store.runtimeLogs.last?.runId, "incoming-run")
    }

    func testNativeDebugFeatureFlagsDisabilitanoSessioneConFallbackSafe() {
        let configuration = DebugServiceConfiguration(
            debugServiceEnabled: false,
            debugDAPLLDBEnabled: true
        )
        let store = DebugStore(nativeDebugConfiguration: configuration)

        store.startNativeDebugSession(targetPath: "/bin/ls")

        XCTAssertEqual(store.nativeSession.status, .idle)
        XCTAssertEqual(store.nativeSession.adapter, "native-debug-disabled")
        XCTAssertTrue(store.nativeSession.callStack.isEmpty)
        XCTAssertTrue(store.nativeSession.watchVariables.isEmpty)
        XCTAssertTrue(store.nativeSession.lastError?.contains("debug_service_enabled") ?? false)
    }

    func testStartNativeDebugSessionStoresCoordinatorMetrics() async {
        let service = DebugService(adapter: RecordingNativeDebugAdapter())
        let store = DebugStore(nativeDebugService: service)

        store.startNativeDebugSession(targetPath: "/tmp/bin/demo-app", arguments: ["--dry-run"])

        for _ in 0..<20 where store.nativeSession.lastCommand != "start" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.nativeSession.lastCommand, "start")
        XCTAssertEqual(store.nativeSession.metrics.totalOperations, 1)
        XCTAssertEqual(store.nativeSession.metrics.lastStage?.stage, .start)
    }
}
