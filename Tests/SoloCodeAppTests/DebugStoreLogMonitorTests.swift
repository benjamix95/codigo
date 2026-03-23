import Foundation
import XCTest
@testable import CoderIDE

@MainActor
final class DebugStoreLogMonitorTests: XCTestCase {
    func testStartDebugSessionAttachesLogMonitorWhenFileDoesNotExistYet() async throws {
        let workspaceURL = makeWorkspaceURL()
        let store = DebugStore()
        defer {
            store.stopLogFileMonitor()
            try? FileManager.default.removeItem(at: workspaceURL)
        }

        store.debugWorkspacePath = workspaceURL.path
        store.activeDebugSessionId = "session-start"

        store.startDebugSession(errorContext: "boom")

        let logPath = store.activeDebugLogPath
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath.path))

        try appendRuntimeLogLine(
            to: logPath,
            id: "entry-start",
            message: "runtime after monitor bootstrap",
            sessionId: "session-start"
        )

        try await waitForRuntimeLogs(in: store, expectedCount: 1)
        XCTAssertEqual(store.runtimeLogs.last?.id, "entry-start")
    }

    func testRestoreSnapshotReattachesRuntimeLogMonitor() async throws {
        let workspaceURL = makeWorkspaceURL()
        let store = DebugStore()
        defer {
            store.stopLogFileMonitor()
            try? FileManager.default.removeItem(at: workspaceURL)
        }

        store.debugWorkspacePath = workspaceURL.path
        store.activeDebugSessionId = "session-restore"
        store.startDebugSession(errorContext: "boom")

        let logPath = store.activeDebugLogPath
        try appendRuntimeLogLine(
            to: logPath,
            id: "entry-before-restore",
            message: "runtime before restore",
            sessionId: "session-restore"
        )
        try await waitForRuntimeLogs(in: store, expectedCount: 1)

        let snapshot = store.snapshot()
        store.resetSession()
        store.restore(from: snapshot)

        try appendRuntimeLogLine(
            to: logPath,
            id: "entry-after-restore",
            message: "runtime after restore",
            sessionId: "session-restore"
        )

        try await waitForRuntimeLogs(in: store, expectedCount: 2)
        XCTAssertEqual(store.runtimeLogs.last?.id, "entry-after-restore")
    }

    private func makeWorkspaceURL() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugStoreLogMonitorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func appendRuntimeLogLine(
        to url: URL,
        id: String,
        message: String,
        sessionId: String
    ) throws {
        let formatter = ISO8601DateFormatter()
        let line = """
        {"id":"\(id)","timestamp":"\(formatter.string(from: Date()))","severity":"info","source":"runtime","message":"\(message)","category":"runtime","session_id":"\(sessionId)"}
        """
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if let data = "\(line)\n".data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func waitForRuntimeLogs(
        in store: DebugStore,
        expectedCount: Int,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if store.runtimeLogs.count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Expected at least \(expectedCount) runtime log(s), got \(store.runtimeLogs.count)")
    }
}
