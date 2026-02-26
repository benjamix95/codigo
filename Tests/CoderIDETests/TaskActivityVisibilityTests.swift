import XCTest
@testable import CoderIDE

@MainActor
final class TaskActivityVisibilityTests: XCTestCase {
    func testConcreteFilterExcludesGenericEvents() {
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("reasoning"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("reasoning_delta"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("thinking"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("thinking_stream"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("turn_started"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("turn_completed"))
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEventType("usage"))
    }

    func testConcreteFilterIncludesOperationalEvents() {
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("command_execution"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("file_change"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("web_search_started"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("todo_write"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("process_paused"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("debug_log"))
    }

    func testStreamingStatusAndDetailIgnoreGenericEvents() {
        let generic = TaskActivity(
            type: "turn_started",
            title: "Turn started",
            phase: .planning,
            isRunning: true
        )
        let usage = TaskActivity(
            type: "usage",
            title: "Token usage",
            phase: .planning,
            isRunning: false
        )
        let concrete = TaskActivity(
            type: "command_execution",
            title: "Running tests",
            phase: .executing,
            isRunning: true
        )

        let activities = [generic, usage, concrete]
        let status = TaskActivityStore.streamingStatusText(
            isPaused: false,
            activities: activities
        )
        let detail = TaskActivityStore.streamingDetailText(
            activities: activities,
            activeOperationsCount: 2
        )

        XCTAssertEqual(status, "Running command")
        XCTAssertEqual(detail, "Running tests • 2 operations")
    }

    func testStreamingStatusAndDetailFallbackWhenOnlyGenericEvents() {
        let activities = [
            TaskActivity(type: "turn_started", title: "Turn started", phase: .planning, isRunning: true),
            TaskActivity(type: "usage", title: "Token usage", phase: .planning, isRunning: false),
        ]

        let status = TaskActivityStore.streamingStatusText(
            isPaused: false,
            activities: activities
        )
        let detail = TaskActivityStore.streamingDetailText(
            activities: activities,
            activeOperationsCount: 0
        )

        XCTAssertEqual(status, "Thinking")
        XCTAssertNil(detail)
    }

    func testHiddenGenericEventRemainsInvisibleEvenWithOperationalPayload() {
        let hidden = TaskActivity(
            type: "thinking",
            title: "Thinking",
            payload: ["command": "swift test"],
            phase: .executing,
            isRunning: true
        )
        XCTAssertFalse(TaskActivityStore.isConcreteVisibleEvent(hidden))
    }
}
