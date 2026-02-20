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
}
