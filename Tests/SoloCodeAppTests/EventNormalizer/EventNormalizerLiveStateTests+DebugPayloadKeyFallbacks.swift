import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
    func testDebugLogUsesCamelCaseToolCallIdForGrouping() {
        let events = EventNormalizer.normalize(
            type: "debug_log",
            payload: [
                "severity": "info",
                "message": "debug message",
                "toolCallId": "dbg-tool-camel-1",
                "status": "started",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_log"
                    && activity.groupId == "dbg-tool-camel-1"
                    && activity.isRunning
            }
            return false
        })
    }

    func testDebugMarkUsesCamelCaseGroupIdForGrouping() {
        let events = EventNormalizer.normalize(
            type: "debug_mark",
            payload: [
                "marker_info": "Sources/App.swift|42|added print",
                "groupId": "dbg-group-camel-1",
                "status": "completed",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_mark"
                    && activity.groupId == "dbg-group-camel-1"
                    && !activity.isRunning
            }
            return false
        })
    }

    func testDebugPhaseUpdateUsesCamelCaseGroupIdWhenProvided() {
        let events = EventNormalizer.normalize(
            type: "debug_phase_update",
            payload: [
                "phase": "verifying",
                "detail": "Running checks",
                "groupId": "dbg-phase-camel-1",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_phase_update"
                    && activity.groupId == "dbg-phase-camel-1"
                    && !activity.isRunning
            }
            return false
        })
    }
}
