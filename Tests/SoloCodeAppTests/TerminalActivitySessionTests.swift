import XCTest
@testable import CoderIDE

final class TerminalActivitySessionTests: XCTestCase {
    func testInitFromActivityUsesCamelCaseIdentifiersWhenSnakeCaseMissing() {
        let activity = TaskActivity(
            type: "command_execution",
            title: "Run command",
            detail: nil,
            payload: [
                "toolCallId": "tc-camel-1",
                "groupId": "grp-camel-1",
                "command": "git status",
            ],
            timestamp: Date(timeIntervalSince1970: 100),
            phase: .executing,
            isRunning: true,
            groupId: nil
        )

        let session = TerminalActivitySession(from: activity)

        XCTAssertEqual(session.toolCallId, "tc-camel-1")
        XCTAssertEqual(session.groupId, "grp-camel-1")
        XCTAssertEqual(session.id, "tc-camel-1")
        XCTAssertEqual(session.command, "git status")
    }

    func testInitFromActivityFallsBackToCamelCaseGroupIdForSessionId() {
        let activity = TaskActivity(
            type: "command_execution",
            title: "Run command",
            detail: nil,
            payload: [
                "groupId": "grp-camel-2",
                "command": "ls -la",
            ],
            timestamp: Date(timeIntervalSince1970: 200),
            phase: .executing,
            isRunning: true,
            groupId: nil
        )

        let session = TerminalActivitySession(from: activity)

        XCTAssertNil(session.toolCallId)
        XCTAssertEqual(session.groupId, "grp-camel-2")
        XCTAssertEqual(session.id, "grp-camel-2")
        XCTAssertEqual(session.command, "ls -la")
    }

    func testInitFromActivityUsesCallIdFallbackWhenToolCallIdKeysMissing() {
        let activity = TaskActivity(
            type: "command_execution",
            title: "Run command",
            detail: nil,
            payload: [
                "callId": "call-camel-9",
                "command": "pwd",
            ],
            timestamp: Date(timeIntervalSince1970: 300),
            phase: .executing,
            isRunning: true,
            groupId: nil
        )

        let session = TerminalActivitySession(from: activity)

        XCTAssertEqual(session.toolCallId, "call-camel-9")
        XCTAssertEqual(session.id, "call-camel-9")
        XCTAssertEqual(session.command, "pwd")
    }

    func testInitFromActivityTreatsCompletedStatusAsNotRunning() {
        let activity = TaskActivity(
            type: "command_execution",
            title: "Run command",
            detail: nil,
            payload: [
                "tool_call_id": "tc-complete-1",
                "status": "completed",
                "command": "swift test",
            ],
            timestamp: Date(timeIntervalSince1970: 400),
            phase: .executing,
            isRunning: true,
            groupId: nil
        )

        let session = TerminalActivitySession(from: activity)

        XCTAssertEqual(session.status, "completed")
        XCTAssertFalse(session.isRunning)
    }

    func testRunningStateUsesStartedStatusEvenWhenFallbackIsFalse() {
        XCTAssertTrue(
            TerminalActivitySession.normalizedRunningState(
                status: "started",
                fallbackIsRunning: false
            )
        )
        XCTAssertFalse(
            TerminalActivitySession.normalizedRunningState(
                status: "completed",
                fallbackIsRunning: true
            )
        )
    }
}
