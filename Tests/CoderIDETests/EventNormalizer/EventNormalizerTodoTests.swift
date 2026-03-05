import XCTest
@testable import CoderIDE

final class EventNormalizerTodoTests: XCTestCase {
    func testTodoWriteShorthandParsesFilesFromLinkedFilesJSON() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "title": "Review patch",
                "status": "in_progress",
                "linkedFiles": #"["Sources/A.swift","Sources/B.swift"]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .todoWrite(let payload) = $0 {
                return payload.title == "Review patch"
                    && payload.files == ["Sources/A.swift", "Sources/B.swift"]
            }
            return false
        })
    }

    func testTodoWriteBatchParsesLinkedFilesAliases() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "todos_json": #"[{"content":"Step A","status":"pending","linked_files":"[\"Sources/X.swift\"]"}]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .todoWrite(let payload) = $0 {
                return payload.title == "Step A"
                    && payload.files == ["Sources/X.swift"]
            }
            return false
        })
    }

    func testTodoWriteBatchEmptyFallsBackToClearMarker() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "todos_json": "[]",
                "title": EventNormalizer.todoClearMarkerTitle,
                "clear_todos": "true",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .todoWrite(let payload) = $0 {
                return payload.title == EventNormalizer.todoClearMarkerTitle
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "todo_write"
                    && activity.detail == "Todo list cleared"
            }
            return false
        })
    }
}
