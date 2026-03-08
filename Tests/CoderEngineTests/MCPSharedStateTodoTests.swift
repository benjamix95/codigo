import Foundation
import XCTest
@testable import CoderEngine

final class MCPSharedStateTodoTests: XCTestCase {
    private var backupTodosData: Data?
    private var todosURL: URL {
        MCPSharedState.todosFilePath
    }

    override func setUpWithError() throws {
        backupTodosData = try? Data(contentsOf: todosURL)
        try? FileManager.default.removeItem(at: todosURL)
    }

    override func tearDownWithError() throws {
        if let backupTodosData {
            try? backupTodosData.write(to: todosURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: todosURL)
        }
    }

    func testCanonicalizationDoesNotMergeDifferentExplicitIDsWithSameTitle() {
        let input: [[String: Any]] = [
            [
                "id": "todo-explicit-a",
                "title": "Allineare KPI baseline",
                "status": "pending",
            ],
            [
                "id": "todo-explicit-b",
                "title": "Allineare KPI baseline",
                "status": "done",
            ],
        ]

        MCPSharedState.writeTodos(input)
        let todos = MCPSharedState.readTodos()

        let matching = todos.filter {
            ($0["title"] as? String) == "Allineare KPI baseline"
        }
        XCTAssertEqual(matching.count, 2)
        let ids = Set(matching.compactMap { $0["id"] as? String })
        XCTAssertEqual(ids, ["todo-explicit-a", "todo-explicit-b"])
    }

    func testCanonicalizationMergesMissingIDsByTitleForLegacyPayloads() {
        let input: [[String: Any]] = [
            [
                "title": "Definire baseline tecnica",
                "status": "pending",
            ],
            [
                "title": "Definire baseline tecnica",
                "status": "done",
            ],
        ]

        MCPSharedState.writeTodos(input)
        let todos = MCPSharedState.readTodos()

        let matching = todos.filter {
            ($0["title"] as? String) == "Definire baseline tecnica"
        }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?["status"] as? String, "done")
    }

    func testCanonicalizationDoesNotMergeExplicitIDWithLegacyMissingIDByTitle() {
        let input: [[String: Any]] = [
            [
                "id": "todo-explicit-keep",
                "title": "Stabilizzare debug session",
                "status": "in_progress",
            ],
            [
                "title": "Stabilizzare debug session",
                "status": "done",
            ],
        ]

        MCPSharedState.writeTodos(input)
        let todos = MCPSharedState.readTodos()

        let matching = todos.filter {
            ($0["title"] as? String) == "Stabilizzare debug session"
        }
        XCTAssertEqual(matching.count, 2)
    }
}
