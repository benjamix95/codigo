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
            XCTFail("Evento taskActivity mancante")
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
            XCTFail("Evento taskActivity mancante")
            return
        }
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.title, "Processo in pausa")
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
            XCTFail("Evento todoWrite mancante")
            return
        }
        XCTAssertEqual(todo.status, .inProgress)
        XCTAssertEqual(todo.priority, .high)
    }

    func testTodoWriteAcceptsTaskAliasWhenTitleMissing() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "task": "Allineare layout chat",
                "status": "pending",
                "priority": "medium"
            ]
        )

        guard case .todoWrite(let todo)? = events.first else {
            XCTFail("Evento todoWrite mancante")
            return
        }
        XCTAssertEqual(todo.title, "Allineare layout chat")
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
                return activity.type == "todo_write" && activity.title == "Todo aggiornato"
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
                "title": "Aggiorna parser"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepUpdate(let stepId, let status, let title) = $0 {
                return stepId == "1" && status == .running && title == "Aggiorna parser"
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_update"
                    && activity.title == "Aggiorna parser"
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
                "title": "Ragionamento",
                "detail": "Analisi interna"
            ]
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testTurnStartedMapsToPlanningRunning() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "turn_started",
            payload: [
                "title": "Turno avviato",
                "status": "started",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Evento taskActivity mancante")
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
                "title": "Turno completato",
                "status": "completed",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Evento taskActivity mancante")
            return
        }
        XCTAssertEqual(activity.type, "turn_completed")
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.groupId, "turn-1")
    }
}
