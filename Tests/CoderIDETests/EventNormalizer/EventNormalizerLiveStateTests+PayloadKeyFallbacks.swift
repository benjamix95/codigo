import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
    func testPlanStepUpdateAcceptsCamelCaseStepIdAndGroupId() {
        let events = EventNormalizer.normalize(
            type: "plan_step_update",
            payload: [
                "stepId": "2",
                "groupId": "plan-camel-2",
                "status": "running",
                "title": "Patch mapper",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepUpdate(let stepId, let status, let title) = $0 {
                return stepId == "2" && status == .running && title == "Patch mapper"
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_update"
                    && activity.groupId == "plan-camel-2"
                    && activity.isRunning
            }
            return false
        })
    }

    func testDefaultNormalizationUsesSnakeCaseQueryIdForGrouping() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "web_search",
            payload: [
                "query": "swift actors",
                "status": "started",
                "query_id": "q-snake-1",
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }

        XCTAssertEqual(activity.type, "web_search_started")
        XCTAssertEqual(activity.groupId, "q-snake-1")
    }

    func testDefaultNormalizationUsesCamelCaseToolCallIdForGrouping() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "command_execution",
            payload: [
                "title": "Run command",
                "command": "echo hello",
                "toolCallId": "tc-camel-42",
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.last else {
            XCTFail("Missing taskActivity event")
            return
        }

        XCTAssertEqual(activity.type, "command_execution")
        XCTAssertEqual(activity.groupId, "tc-camel-42")
    }
}
