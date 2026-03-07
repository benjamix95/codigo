import XCTest
@testable import CoderIDE

@MainActor
final class TerminalSessionStoreTests: XCTestCase {

    // MARK: - Session creation

    func testCreateSessionAddsToList() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Shell 1", cwd: "/tmp", isAgent: false)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, session.id)
        XCTAssertEqual(store.sessions.first?.label, "Shell 1")
        XCTAssertEqual(store.sessions.first?.isAgentOwned, false)
    }

    func testCreateMultipleSessions() {
        let store = TerminalSessionStore()
        store.createSession(label: "Shell 1", cwd: "/tmp", isAgent: false)
        store.createSession(label: "Shell 2", cwd: "/home", isAgent: false)
        store.createSession(label: "Agent: build", cwd: "/project", isAgent: true)
        XCTAssertEqual(store.sessions.count, 3)
    }

    func testAgentSessionBecomesActive() {
        let store = TerminalSessionStore()
        let user = store.createSession(label: "Shell", cwd: "/tmp", isAgent: false)
        XCTAssertEqual(store.activeSessionId, user.id)

        let agent = store.createSession(label: "Agent: test", cwd: "/tmp", isAgent: true)
        XCTAssertEqual(store.activeSessionId, agent.id)
    }

    func testFirstSessionBecomesActiveWhenNoneSet() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Shell", cwd: "/tmp", isAgent: false)
        XCTAssertEqual(store.activeSessionId, session.id)
    }

    // MARK: - Session closing

    func testCloseSessionRemovesIt() {
        let store = TerminalSessionStore()
        let s1 = store.createSession(label: "Shell 1", cwd: nil, isAgent: false)
        let s2 = store.createSession(label: "Shell 2", cwd: nil, isAgent: false)
        store.closeSession(id: s1.id)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id, s2.id)
    }

    func testCloseActiveSessionSwitchesToFirst() {
        let store = TerminalSessionStore()
        let s1 = store.createSession(label: "Shell 1", cwd: nil, isAgent: false)
        let s2 = store.createSession(label: "Shell 2", cwd: nil, isAgent: true)
        XCTAssertEqual(store.activeSessionId, s2.id)
        store.closeSession(id: s2.id)
        XCTAssertEqual(store.activeSessionId, s1.id)
    }

    func testCloseLastSessionClearsActive() {
        let store = TerminalSessionStore()
        let s1 = store.createSession(label: "Shell", cwd: nil, isAgent: false)
        store.closeSession(id: s1.id)
        XCTAssertNil(store.activeSessionId)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // MARK: - Output buffer

    func testAppendAndReadOutput() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Shell", cwd: nil, isAgent: false)
        store.appendOutput(sessionId: session.id, text: "hello ")
        store.appendOutput(sessionId: session.id, text: "world")
        let output = store.readOutput(sessionId: session.id)
        XCTAssertEqual(output, "hello world")
    }

    func testReadOutputTruncatesFromEnd() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Shell", cwd: nil, isAgent: false)
        store.appendOutput(sessionId: session.id, text: "abcdefghij")
        let output = store.readOutput(sessionId: session.id, lastN: 5)
        XCTAssertEqual(output, "fghij")
    }

    func testReadOutputFromActiveSession() {
        let store = TerminalSessionStore()
        let session = store.createSession(label: "Shell", cwd: nil, isAgent: false)
        store.appendOutput(sessionId: session.id, text: "active output")
        let output = store.readOutput()
        XCTAssertEqual(output, "active output")
    }

    func testReadOutputFromNonExistentSessionReturnsEmpty() {
        let store = TerminalSessionStore()
        let output = store.readOutput(sessionId: UUID())
        XCTAssertEqual(output, "")
    }

    // MARK: - Buffer limit

    func testOutputBufferRingBehavior() {
        let session = TerminalSession(label: "Test", isAgentOwned: false)
        let bigChunk = String(repeating: "x", count: 70_000)
        session.appendOutput(bigChunk)
        XCTAssertLessThanOrEqual(session.outputLength, 64_000)
        let output = session.readOutput(lastN: 100)
        XCTAssertEqual(output.count, 100)
        XCTAssertTrue(output.allSatisfy { $0 == "x" })
    }

    // MARK: - Ensure default session

    func testEnsureDefaultSessionCreatesOneWhenEmpty() {
        let store = TerminalSessionStore()
        store.ensureDefaultSession(cwd: "/workspace")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.label, "Shell")
        XCTAssertEqual(store.sessions.first?.workingDirectory, "/workspace")
        XCTAssertEqual(store.sessions.first?.isAgentOwned, false)
    }

    func testEnsureDefaultSessionDoesNotDuplicate() {
        let store = TerminalSessionStore()
        store.createSession(label: "Existing", cwd: nil, isAgent: false)
        store.ensureDefaultSession(cwd: "/workspace")
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.label, "Existing")
    }

    // MARK: - All sessions summary

    func testAllSessionsSummaryWithNoSessions() {
        let store = TerminalSessionStore()
        XCTAssertEqual(store.readAllSessionsSummary(), "(no terminal sessions)")
    }

    func testAllSessionsSummaryWithMultipleSessions() {
        let store = TerminalSessionStore()
        let s1 = store.createSession(label: "User Shell", cwd: "/home", isAgent: false)
        let s2 = store.createSession(label: "Agent Build", cwd: "/project", isAgent: true)
        store.appendOutput(sessionId: s1.id, text: "$ ls\nfile1.txt")
        store.appendOutput(sessionId: s2.id, text: "Building...")
        let summary = store.readAllSessionsSummary()
        XCTAssertTrue(summary.contains("User Shell"))
        XCTAssertTrue(summary.contains("Agent Build"))
        XCTAssertTrue(summary.contains("user"))
        XCTAssertTrue(summary.contains("agent"))
        XCTAssertTrue(summary.contains("file1.txt"))
        XCTAssertTrue(summary.contains("Building..."))
    }

    // MARK: - Session lookup

    func testSessionLookupById() {
        let store = TerminalSessionStore()
        let s1 = store.createSession(label: "Shell 1", cwd: nil, isAgent: false)
        store.createSession(label: "Shell 2", cwd: nil, isAgent: false)
        XCTAssertEqual(store.session(for: s1.id)?.label, "Shell 1")
    }

    func testSessionLookupForNonExistentIdReturnsNil() {
        let store = TerminalSessionStore()
        XCTAssertNil(store.session(for: UUID()))
    }

    // MARK: - Active session

    func testActiveSessionReturnsFirstWhenNoActiveSet() {
        let store = TerminalSessionStore()
        store.createSession(label: "First", cwd: nil, isAgent: false)
        store.createSession(label: "Second", cwd: nil, isAgent: false)
        store.activeSessionId = nil
        XCTAssertEqual(store.activeSession?.label, "First")
    }

    func testActiveSessionReturnsCorrectSession() {
        let store = TerminalSessionStore()
        store.createSession(label: "First", cwd: nil, isAgent: false)
        let second = store.createSession(label: "Second", cwd: nil, isAgent: false)
        store.activeSessionId = second.id
        XCTAssertEqual(store.activeSession?.label, "Second")
    }

    // MARK: - Session clear output

    func testClearOutputEmptiesBuffer() {
        let session = TerminalSession(label: "Test", isAgentOwned: false)
        session.appendOutput("some text")
        XCTAssertFalse(session.readOutput().isEmpty)
        session.clearOutput()
        XCTAssertTrue(session.readOutput().isEmpty)
        XCTAssertEqual(session.outputLength, 0)
    }
}
