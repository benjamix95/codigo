import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class TerminalBridgeIntegrationTests: XCTestCase {

    func testTerminalSessionStoreConformsToTerminalBridge() {
        let store = TerminalSessionStore()
        let bridge: any TerminalBridge = store
        XCTAssertNotNil(bridge)
    }

    func testReadTerminalOutputViaProtocol() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Test", cwd: "/tmp", isAgent: true)
        store.appendOutput(sessionId: session.id, text: "hello from terminal")

        let bridge: any TerminalBridge = store
        let output = bridge.readTerminalOutput(sessionId: session.id.uuidString, lastN: 8000)
        XCTAssertEqual(output, "hello from terminal")
    }

    func testReadTerminalOutputNilSessionUsesActive() {
        let store = TerminalSessionStore()
        _ = store.createSession(label: "User", cwd: nil, isAgent: false)
        let session = store.createSession(label: "Active", cwd: nil, isAgent: true)
        store.appendOutput(sessionId: session.id, text: "active content")

        let bridge: any TerminalBridge = store
        let output = bridge.readTerminalOutput(sessionId: nil, lastN: 8000)
        XCTAssertEqual(output, "active content")
    }

    func testAllSessionsSummaryViaProtocol() {
        let store = TerminalSessionStore()
        _ = store.createSession(label: "User shell", cwd: "/home", isAgent: false)
        let s1 = store.createSession(label: "Agent shell", cwd: "/home", isAgent: true)
        store.appendOutput(sessionId: s1.id, text: "user data")

        let bridge: any TerminalBridge = store
        let summary = bridge.allSessionsSummary(lastN: 2000)
        XCTAssertTrue(summary.contains("Agent shell"))
        XCTAssertFalse(summary.contains("User shell"))
        XCTAssertTrue(summary.contains("user data"))
    }

    func testReadTerminalOutputRejectsUserOwnedSession() {
        let store = TerminalSessionStore()
        let userSession = store.createSession(label: "User", cwd: "/tmp", isAgent: false)
        store.appendOutput(sessionId: userSession.id, text: "sensitive user output")

        let bridge: any TerminalBridge = store
        let output = bridge.readTerminalOutput(sessionId: userSession.id.uuidString, lastN: 8000)
        XCTAssertEqual(output, "")
    }

    func testAllSessionsSummaryWhenNoAgentSessions() {
        let store = TerminalSessionStore()
        let userSession = store.createSession(label: "User", cwd: "/tmp", isAgent: false)
        store.appendOutput(sessionId: userSession.id, text: "sensitive user output")

        let bridge: any TerminalBridge = store
        let summary = bridge.allSessionsSummary(lastN: 2000)
        XCTAssertEqual(summary, "(no agent terminal sessions)")
    }

    func testLongRunningCommandDetection() {
        let longPatterns = [
            "swift build", "swift test", "npm run dev",
            "cargo build", "python script.py", "make all",
            "docker compose up", "yarn start"
        ]
        let shortPatterns = [
            "ls", "cat file.txt", "echo hello", "mkdir dir",
            "git status", "rm -rf build"
        ]

        let longRunningPatterns = [
            "npm run", "npm start", "npm test", "yarn ", "pnpm ",
            "swift build", "swift test", "swift run",
            "cargo build", "cargo run", "cargo test",
            "make", "cmake", "gradle",
            "python ", "python3 ", "node ",
            "docker ", "kubectl ",
            "xcodebuild", "fastlane",
            "serve", "watch", "dev"
        ]

        for cmd in longPatterns {
            let lower = cmd.lowercased()
            let isLong = longRunningPatterns.contains(where: { lower.contains($0) })
            XCTAssertTrue(isLong, "'\(cmd)' should be detected as long-running")
        }

        for cmd in shortPatterns {
            let lower = cmd.lowercased()
            let isLong = longRunningPatterns.contains(where: { lower.contains($0) })
            XCTAssertFalse(isLong, "'\(cmd)' should NOT be detected as long-running")
        }
    }
}
