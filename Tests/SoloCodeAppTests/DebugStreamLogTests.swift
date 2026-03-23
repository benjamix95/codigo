import Combine
import XCTest
@testable import CoderIDE

// MARK: - DebugStreamLogger Tests

final class DebugStreamLoggerTests: XCTestCase {
    func testLogPathIsOutsideProjectDirectory() {
        let url = DebugStreamLogger.logFileURL
        let path = url.path

        XCTAssertTrue(
            path.contains("/Library/Caches/SoloCode"),
            "Log file should reside in ~/Library/Caches/SoloCode, got: \(path)"
        )
        XCTAssertFalse(
            path.contains("/SoloCode/App") || path.contains("/SoloCode/.cursor"),
            "Log file must NOT reside inside the project tree"
        )
    }

    func testLogDirectoryIsCreated() {
        let dir = DebugStreamLogger.logDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        XCTAssertTrue(exists && isDir.boolValue)
    }

    func testClearLogFileTruncatesContent() {
        DebugStreamLogger.log("test", "pre-clear entry")
        DebugStreamLogger.clearLogFile()

        let content = (try? String(contentsOf: DebugStreamLogger.logFileURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(content.isEmpty, "File should be empty after clearLogFile()")
    }

    func testLogRelayEmitsEvent() {
        let expectation = expectation(description: "relay emits")
        var received: DebugStreamLogger.LogEvent?
        let cancellable = DebugStreamLogger.logRelay.sink { event in
            received = event
            expectation.fulfill()
        }

        DebugStreamLogger.log("test:relay", "relay check")

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(received?.message, "relay check")
        cancellable.cancel()
    }
}

// MARK: - DebugStore Stream Logs Tests

@MainActor
final class DebugStoreStreamLogTests: XCTestCase {

    // MARK: - Basic Operations

    func testClearStreamLogsResetsArrayAndCount() {
        let store = DebugStore()
        store.streamLogs.append(DebugStreamLogEntry(message: "a"))
        store.streamLogs.append(DebugStreamLogEntry(message: "b"))
        store.streamLogNewCount = 2

        store.clearStreamLogs()

        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    // MARK: - Phase Transitions Clear Stream Logs

    func testSetPhaseClearsStreamLogsOnValidTransition() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.streamLogs.append(DebugStreamLogEntry(message: "describing-phase log"))
        store.streamLogNewCount = 1

        let result = store.setPhase(.reproducing)

        XCTAssertTrue(result)
        XCTAssertEqual(store.phase, .reproducing)
        XCTAssertTrue(store.streamLogs.isEmpty, "Stream logs must be cleared on phase transition")
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    func testSetPhaseSamePhaseDoesNotClearStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.setPhase(.reproducing)
        store.streamLogs.append(DebugStreamLogEntry(message: "keep me"))
        store.streamLogNewCount = 1

        let result = store.setPhase(.reproducing)

        XCTAssertTrue(result)
        XCTAssertEqual(store.streamLogs.count, 1, "Same-phase re-entry should NOT clear stream logs")
    }

    func testInvalidPhaseTransitionDoesNotClearStreamLogs() {
        let store = DebugStore()
        store.streamLogs.append(DebugStreamLogEntry(message: "keep"))
        store.streamLogNewCount = 1

        store.setPhase(.verifying)

        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(store.streamLogs.count, 1)
    }

    // MARK: - Session Lifecycle

    func testResetSessionClearsStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "x")
        store.streamLogs.append(DebugStreamLogEntry(message: "leftover"))
        store.streamLogNewCount = 5

        store.resetSession()

        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    func testStartDebugSessionClearsStreamLogs() {
        let store = DebugStore()
        store.streamLogs.append(DebugStreamLogEntry(message: "stale"))
        store.streamLogNewCount = 3

        store.startDebugSession(errorContext: "fresh")

        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    // MARK: - Mark Fixed / Cleanup

    func testApplyDebugCleanSuccessClearsStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.phase = .verifying
        _ = store.beginMarkFixed(summary: "done")
        store.streamLogs.append(DebugStreamLogEntry(message: "debug noise"))
        store.streamLogNewCount = 10

        store.applyDebugCleanResult(success: true, detail: "cleaned")

        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
        XCTAssertEqual(store.phase, .resolved)
    }

    func testApplyDebugCleanFailureDoesNotClearStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.phase = .verifying
        _ = store.beginMarkFixed(summary: "try")
        store.streamLogs.append(DebugStreamLogEntry(message: "important"))
        store.streamLogNewCount = 1

        store.applyDebugCleanResult(success: false, detail: "perm denied")

        XCTAssertEqual(store.streamLogs.count, 1, "Failure should preserve stream logs for investigation")
        XCTAssertEqual(store.phase, .verifying)
    }

    func testLegacyMarkFixedClearsStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")
        store.phase = .verifying
        store.streamLogs.append(DebugStreamLogEntry(message: "old"))
        store.streamLogNewCount = 4

        _ = store.markFixed(summary: "resolved")

        XCTAssertTrue(store.streamLogs.isEmpty)
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    // MARK: - Reproduce Flow

    func testConfirmReproducedClearsStreamLogs() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "crash")
        store.setPhase(.reproducing)
        store.streamLogs.append(DebugStreamLogEntry(message: "reproduce log"))
        store.streamLogNewCount = 2

        store.confirmReproduced()

        XCTAssertEqual(store.phase, .fixing)
        XCTAssertTrue(store.streamLogs.isEmpty, "Stream logs must be cleared when moving to fix phase")
        XCTAssertEqual(store.streamLogNewCount, 0)
    }

    // MARK: - Full Debug Cycle

    func testFullDebugCycleClearsStreamLogsAtEachPhase() {
        let store = DebugStore()
        store.startDebugSession(errorContext: "bug")

        store.streamLogs.append(DebugStreamLogEntry(message: "describe"))
        store.streamLogNewCount = 1
        store.setPhase(.reproducing)
        XCTAssertTrue(store.streamLogs.isEmpty, "Cleared on describe->reproducing")

        store.streamLogs.append(DebugStreamLogEntry(message: "repro"))
        store.streamLogNewCount = 2
        store.confirmReproduced()
        XCTAssertTrue(store.streamLogs.isEmpty, "Cleared on reproducing->fixing")

        store.streamLogs.append(DebugStreamLogEntry(message: "fix"))
        store.streamLogNewCount = 3
        store.setPhase(.verifying)
        XCTAssertTrue(store.streamLogs.isEmpty, "Cleared on fixing->verifying")

        store.streamLogs.append(DebugStreamLogEntry(message: "verify"))
        store.streamLogNewCount = 1
        _ = store.beginMarkFixed(summary: "done")
        store.applyDebugCleanResult(success: true, detail: "ok")
        XCTAssertTrue(store.streamLogs.isEmpty, "Cleared on mark-fixed")
        XCTAssertEqual(store.phase, .resolved)
    }
}
