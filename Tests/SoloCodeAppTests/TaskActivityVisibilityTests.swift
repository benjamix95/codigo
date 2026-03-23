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
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("plan_create"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("plan_step_batch_update"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("plan_request_user_input"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("process_paused"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("debug_log"))
        XCTAssertTrue(TaskActivityStore.isConcreteVisibleEventType("subagent_text"))
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

    func testAssistantUpdateTextPrefersLatestOperationalDetail() {
        let activities = [
            TaskActivity(
                type: "assistant_update",
                title: "Working",
                detail: "Analizzo il pannello debug",
                phase: .executing,
                isRunning: true
            ),
            TaskActivity(
                type: "assistant_update",
                title: "Working",
                detail: "Verifico lo stato del consumer eventi",
                phase: .executing,
                isRunning: true
            ),
        ]

        XCTAssertEqual(
            TaskActivityStore.assistantUpdateText(in: activities),
            "Verifico lo stato del consumer eventi"
        )
    }

    func testAssistantUpdateTextReturnsNilWhenAbsent() {
        let activities = [
            TaskActivity(type: "command_execution", title: "Run tests", phase: .executing, isRunning: true),
        ]

        XCTAssertNil(TaskActivityStore.assistantUpdateText(in: activities))
    }

    func testStreamingStatusPrefersRespondingForAssistantUpdates() {
        let activities = [
            TaskActivity(
                type: "assistant_update",
                title: "Sto rispondendo",
                detail: "Analizzo la timeline",
                phase: .executing,
                isRunning: true
            ),
        ]

        XCTAssertEqual(
            TaskActivityStore.streamingStatusText(
                isPaused: false,
                activities: activities
            ),
            "Responding"
        )
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

    func testTimelineOrderingKeepsReasoningBetweenAnswerAndOperationalDetails() {
        let visible = ChatTurnTimelineOrdering.visibleBlocks(
            from: [
                PersistedChatTimelineBlock(id: "primary", kind: .primaryText, text: "Answer"),
                PersistedChatTimelineBlock(
                    id: "reasoning",
                    kind: .reasoning,
                    title: "Thinking",
                    text: "I am planning the next step."
                ),
                PersistedChatTimelineBlock(id: "status", kind: .status, text: "Running"),
                PersistedChatTimelineBlock(id: "plan", kind: .plan, text: "Do X"),
            ]
        )

        XCTAssertEqual(visible.map(\.kind), [.primaryText, .reasoning, .plan])
        XCTAssertEqual(
            ChatTurnTimelineOrdering.narrativeBlocks(from: visible).map(\.kind),
            [.reasoning]
        )
        XCTAssertEqual(
            ChatTurnTimelineOrdering.detailBlocks(from: visible).map(\.kind),
            [.plan]
        )
    }

    func testTimelineOrderingExcludesOperationalTraceBucketsFromNarrativeBlocks() {
        let visible = ChatTurnTimelineOrdering.visibleBlocks(
            from: [
                PersistedChatTimelineBlock(id: "primary", kind: .primaryText, text: "Answer"),
                PersistedChatTimelineBlock(id: "commands", kind: .commands, items: ["swift test"]),
                PersistedChatTimelineBlock(id: "files", kind: .files, items: ["App.swift"]),
                PersistedChatTimelineBlock(id: "tool-trace", kind: .toolTrace, text: "trace"),
            ]
        )

        XCTAssertEqual(visible.map(\.kind), [.primaryText])
        XCTAssertTrue(ChatTurnTimelineOrdering.narrativeBlocks(from: visible).isEmpty)
        XCTAssertTrue(ChatTurnTimelineOrdering.detailBlocks(from: visible).isEmpty)
    }
}
