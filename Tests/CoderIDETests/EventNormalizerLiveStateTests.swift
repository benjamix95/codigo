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

    func testProcessPausedMapsToThinkingAndStopped() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "process_paused",
            payload: [:]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Evento taskActivity mancante")
            return
        }
        XCTAssertEqual(activity.phase, .thinking)
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
}
