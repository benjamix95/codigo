import XCTest
@testable import CoderIDE

final class EventNormalizerLiveStateTests: XCTestCase {
    func testWebSearchStatusMapsToSearchingPhase() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "web_search",
            payload: [
                "title": "Search",
                "query": "swiftui timeline",
                "status": "started",
                "queryId": "q1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "web_search_started")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertTrue(activity.isRunning)
        XCTAssertEqual(activity.groupId, "q1")
    }

    func testProcessPausedMapsToPlanningAndStopped() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "process_paused",
            payload: [:]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.title, "Process paused")
        XCTAssertNil(activity.groupId)
    }

    func testTodoWriteNormalizesDashedStatus() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "title": "Refactor parser",
                "status": "in-progress",
                "priority": "high"
            ]
        )

        guard case .todoWrite(let todo)? = events.first else {
            XCTFail("Missing todoWrite event")
            return
        }
        XCTAssertEqual(todo.status, .inProgress)
        XCTAssertEqual(todo.priority, .high)
    }

    func testTodoWriteAcceptsTaskAliasWhenTitleMissing() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "task": "Align chat layout",
                "status": "pending",
                "priority": "medium"
            ]
        )

        guard case .todoWrite(let todo)? = events.first else {
            XCTFail("Missing todoWrite event")
            return
        }
        XCTAssertEqual(todo.title, "Align chat layout")
        XCTAssertEqual(todo.status, .pending)
    }

    func testTodoWriteAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "title": "Fix stream reasoning",
                "status": "in_progress",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .todoWrite = $0 { return true }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "todo_write" && activity.title == "Todo updated"
            }
            return false
        })
    }

    func testTodoReadAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "todo_read",
            payload: [:]
        )

        XCTAssertTrue(events.contains {
            if case .todoRead = $0 { return true }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 { return activity.type == "todo_read" }
            return false
        })
    }

    func testPlanStepUpdateAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "plan_step_update",
            payload: [
                "step_id": "1",
                "status": "running",
                "title": "Update parser"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepUpdate(let stepId, let status, let title) = $0 {
                return stepId == "1" && status == .running && title == "Update parser"
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_update"
                    && activity.title == "Update parser"
                    && activity.phase == .planning
                    && activity.isRunning
            }
            return false
        })
    }

    func testReasoningEventsAreIgnored() {
        let events = EventNormalizer.normalize(
            type: "reasoning",
            payload: [
                "title": "Reasoning",
                "detail": "Internal analysis"
            ]
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testTurnStartedMapsToPlanningRunning() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "turn_started",
            payload: [
                "title": "Turn started",
                "status": "started",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "turn_started")
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertTrue(activity.isRunning)
        XCTAssertEqual(activity.groupId, "turn-1")
    }

    func testTurnCompletedMapsToPlanningStopped() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "turn_completed",
            payload: [
                "title": "Turn completed",
                "status": "completed",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "turn_completed")
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.groupId, "turn-1")
    }

    func testReadBatchCompletedSemanticSearchMapsToSemanticType() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "read_batch_completed",
            payload: [
                "tool": "semantic_search",
                "status": "completed",
                "query": "authentication flow"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "semantic_search")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertFalse(activity.isRunning)
    }

    func testStrReplaceNormalizesToFileChangeEditingPhase() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "str_replace",
            payload: [
                "title": "Edited Config.swift",
                "path": "Sources/CoderIDE/Config.swift",
                "tool": "str_replace",
            ]
        )

        XCTAssertEqual(envelope.kind, .fileUpdate)
        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "file_change")
        XCTAssertEqual(activity.phase, .editing)
    }

    func testCommandExecutionGrepEmitsInstantGrep() {
        let events = EventNormalizer.normalize(
            type: "command_execution",
            payload: [
                "command": "grep -n \"policy\" Sources/CoderIDE/ChatPanelView.swift",
                "cwd": "/Users/test/repo",
                "output": "Sources/CoderIDE/ChatPanelView.swift:10:policy"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .instantGrep = $0 { return true }
            return false
        })
    }

    func testCommandExecutionCatEmitsSyntheticReadActivity() {
        let events = EventNormalizer.normalize(
            type: "command_execution",
            payload: [
                "command": "cat Sources/CoderIDE/ToolTraceVisibility.swift",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "read_batch_completed"
                    && activity.payload["source"] == "synthetic_command_read"
            }
            return false
        })
    }
}
