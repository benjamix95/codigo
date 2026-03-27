import XCTest
@testable import CoderEngine

final class DebugLogServerPersistenceTests: XCTestCase {
    func testAppendPersistsEntriesToGlobalAndSessionLogs() async throws {
        let server = DebugLogServer(maxEntries: 16)
        await server.clear()

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("debug-log-server-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sessionId = await server.startSession(workspacePath: workspace.path)
        await server.logRuntime(source: "runtime", message: "first")
        await server.logRuntime(source: "runtime", message: "second")
        await server.endSession()

        let globalLogURL = await server.logFileURL
        let sessionLogURL = await server.activeSessionLogFileURL

        let globalContent = try String(contentsOf: globalLogURL, encoding: .utf8)
        XCTAssertTrue(globalContent.contains("Debug session started"))
        XCTAssertTrue(globalContent.contains("\"message\":\"first\""))
        XCTAssertTrue(globalContent.contains("\"message\":\"second\""))

        let expectedSessionLogURL = DebugLogServer.sessionLogFileURL(
            workspacePath: workspace.path,
            sessionId: sessionId
        )
        let sessionContent = try String(contentsOf: expectedSessionLogURL, encoding: .utf8)
        XCTAssertTrue(sessionContent.contains("\"sessionId\":\"\(sessionId)\""))
        XCTAssertTrue(sessionContent.contains("\"message\":\"first\""))
        XCTAssertTrue(sessionContent.contains("\"message\":\"second\""))

        XCTAssertNil(sessionLogURL, "Il session log attivo deve essere chiuso dopo endSession")
        await server.clear()
    }
}
