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
        store.streamLogs.append(DebugStreamLogEntry(message: "old stream log"))
        store.streamLogNewCount = 5
        store.activeDebugSessionId = "session-1"
        store.debugWorkspacePath = "/tmp/workspace"
        store.lastTraceAnalysis = "old trace"
        store.lastSnapshotReport = "old snapshot"
        store.lastTimelineReport = "old timeline"
        store.lastTestCheckReport = "old tests"
        store.lastSessionExport = "old export"
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
        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
        XCTAssertEqual(store.activeDebugSessionId, "session-1")
        XCTAssertEqual(store.debugWorkspacePath, "/tmp/workspace")
        XCTAssertTrue(store.lastTraceAnalysis.isEmpty)
        XCTAssertTrue(store.lastSnapshotReport.isEmpty)
        XCTAssertTrue(store.lastTimelineReport.isEmpty)
        XCTAssertTrue(store.lastTestCheckReport.isEmpty)
        XCTAssertTrue(store.lastSessionExport.isEmpty)
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

    func testRestoreFromSnapshotReschedulesDebugCleanFallbackWhenAwaitingClean() {
        let active = DebugStore()
        active.startDebugSession(errorContext: "boom")
        active.phase = .verifying
        _ = active.beginMarkFixed(summary: "done")
        XCTAssertNotNil(active.debugCleanAwaitingTask)
        let snap = active.snapshot()

        let restored = DebugStore()
        restored.restore(from: snap)

        XCTAssertTrue(restored.awaitingDebugClean)
        XCTAssertEqual(restored.phase, .verifying)
        XCTAssertNotNil(
            restored.debugCleanAwaitingTask,
            "restore deve ripianificare il timeout Mark Fixed → debug_clean"
        )
    }

    func testRestoreFromSnapshotReschedulesIdleWarningWhenPhaseActive() {
        let active = DebugStore()
        active.startDebugSession(errorContext: "ctx")
        XCTAssertNotNil(active.sessionIdleWarningTask)
        let snap = active.snapshot()
        active.cancelDebugSessionWatchdogTasks()
        XCTAssertNil(active.sessionIdleWarningTask)

        active.restore(from: snap)

        XCTAssertNotNil(
            active.sessionIdleWarningTask,
            "restore con fase attiva deve riavviare l’avviso idle"
        )
    }

    func testRestoreFromSnapshotCancelsStaleWatchdogTasksBeforeApplyingSnapshot() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "a")
        _ = store.beginMarkFixed(summary: "x")
        let task = store.debugCleanAwaitingTask
        XCTAssertNotNil(task)

        var idleSnap = store.snapshot()
        idleSnap.phase = .idle
        idleSnap.awaitingDebugClean = false
        store.restore(from: idleSnap)

        XCTAssertFalse(store.awaitingDebugClean)
        XCTAssertNil(store.debugCleanAwaitingTask)
    }

    func testSessionSnapshotPreservesFindingsAndStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "ctx")
        let finding = DebugFinding(title: "Leak", filePath: "App.swift", lineNumber: 10)
        store.debugFindings = [finding]
        store.streamLogs = [DebugStreamLogEntry(message: "chunk")]
        store.streamLogNewCount = 7

        let snap = store.snapshot()
        let restored = DebugStore()
        restored.restore(from: snap)

        XCTAssertEqual(restored.debugFindings.count, 1)
        XCTAssertEqual(restored.debugFindings.first?.title, "Leak")
        XCTAssertEqual(restored.streamLogs.count, 1)
        XCTAssertEqual(restored.streamLogs.first?.message, "chunk")
        XCTAssertEqual(restored.streamLogNewCount, 7)
    }

    func testBeginMarkFixedWaitsForDebugCleanBeforeResolving() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "boom")
        store.phase = .verifying
        store.addDebugMarker(DebugMarker(filePath: "A.swift", lineNumber: 12, markerComment: "legacy"))
        store.addInstrumentation(filePath: "A.swift", lineNumber: 14, type: .logging, code: "print(1)")
        store.streamLogs.append(DebugStreamLogEntry(message: "stale log"))
        store.streamLogNewCount = 3

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
        XCTAssertTrue(store.streamLogs.isEmpty, "Stream logs must be cleared on mark-fixed")
        XCTAssertEqual(store.streamLogNewCount, 0)
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
        store.activeDebugSessionId = "session-1"
        store.debugWorkspacePath = "/tmp/workspace"

        store.resetSession()

        XCTAssertEqual(store.severityFilter, Set(DebugEntrySeverity.allCases))
        XCTAssertNil(store.categoryFilter)
        XCTAssertEqual(store.searchQuery, "")
        XCTAssertNil(store.activeDebugSessionId)
        XCTAssertNil(store.debugWorkspacePath)
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

    func testSessionMetricsAggregatesLifecycleCounters() async {
        let service = DebugService(adapter: RecordingNativeDebugAdapter())
        let store = DebugStore(nativeDebugService: service)

        store.startNativeDebugSession(targetPath: "/tmp/bin/demo-app", arguments: ["--dry-run"])
        for _ in 0..<20 where store.nativeSession.lastCommand != "start" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        store.refreshNativeDebugSession()
        for _ in 0..<20 where store.nativeSession.lastCommand != "refresh" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.nativeSession.sessionMetrics.totalOperations, 2)
        XCTAssertEqual(store.nativeSession.sessionMetrics.successfulOperations, 2)
        XCTAssertEqual(store.nativeSession.sessionMetrics.failedOperations, 0)
        XCTAssertGreaterThanOrEqual(store.nativeSession.sessionMetrics.averageDurationMs, 0)
    }
}
