import XCTest
@testable import CoderEngine

extension CodeReviewMultiSwarmProviderTests {
    // MARK: - parseTasksJSON

    func testParseTasksJSON_validTasks() {
        let json = """
        [
          {"id": "r-0", "description": "Fix bug", "files": ["a.swift"], "severity": "critical"},
          {"id": "r-1", "description": "Cleanup", "files": ["b.swift"], "severity": "warning"}
        ]
        """
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: nil)
        if case .tasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 2)
            XCTAssertEqual(tasks[0].id, "r-0")
            XCTAssertEqual(tasks[0].files, ["a.swift"])
            XCTAssertEqual(tasks[1].severity, "warning")
        } else {
            XCTFail("Expected .tasks but got invalidJSON")
        }
    }

    func testParseTasksJSON_filtersEmptyFiles() {
        let json = """
        [{"id": "r-0", "description": "Fix", "files": ["", "  "], "severity": "warning"}]
        """
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: nil)
        // Entries with all-empty files are skipped; when no valid tasks remain,
        // the parser returns .invalidJSON (not empty .tasks).
        if case .invalidJSON = result {
            // expected
        } else {
            XCTFail("Expected .invalidJSON when all files are blank")
        }
    }

    func testParseTasksJSON_filtersToAllowedFiles() {
        let json = """
        [
          {"id": "r-0", "description": "Fix", "files": ["a.swift", "b.swift"], "severity": "critical"}
        ]
        """
        let allowed: Set<String> = ["a.swift"]
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: allowed)
        if case .tasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks[0].files, ["a.swift"])
        } else {
            XCTFail("Expected .tasks")
        }
    }

    func testParseTasksJSON_invalidJSON() {
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON("not json", allowedFiles: nil)
        if case .invalidJSON = result {
            // expected
        } else {
            XCTFail("Expected .invalidJSON")
        }
    }

    func testParseTasksJSON_defaultsForMissingFields() {
        let json = """
        [{"files": ["x.swift"]}]
        """
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: nil)
        if case .tasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks[0].id, "review-0")
            XCTAssertEqual(tasks[0].description, "Fix issues in assigned files")
        } else {
            XCTFail("Expected .tasks")
        }
    }

    func testParseTasksJSON_normalizesDuplicateWorkerIDs() {
        let json = """
        [
          {"id": "review-0", "description": "Fix A", "files": ["a.swift"], "severity": "warning"},
          {"id": "review-0", "description": "Fix B", "files": ["b.swift"], "severity": "critical"}
        ]
        """
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: nil)
        if case .tasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 2)
            XCTAssertEqual(tasks[0].id, "review-0")
            XCTAssertEqual(tasks[1].id, "review-1")
            XCTAssertNotEqual(tasks[0].id, tasks[1].id)
        } else {
            XCTFail("Expected .tasks")
        }
    }

    func testParseTasksJSON_dedupesAndTrimsFilesWithinTask() {
        let json = """
        [
          {"id": "review-0", "description": "Fix A", "files": [" a.swift ", "a.swift", "b.swift", "  "], "severity": "warning"}
        ]
        """
        let result = CodeReviewMultiSwarmProvider.parseTasksJSON(json, allowedFiles: nil)
        if case .tasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks[0].files, ["a.swift", "b.swift"])
        } else {
            XCTFail("Expected .tasks")
        }
    }

    // MARK: - extractReviewTasksJSON

    func testExtractReviewTasksJSON_fromCodeBlock() {
        let text = """
        Here is my analysis:

        ```json
        [{"id":"t1","description":"Fix","files":["a.swift"],"severity":"critical"}]
        ```

        Done.
        """
        let result = CodeReviewMultiSwarmProvider.extractReviewTasksJSON(from: text)
        if case .jsonTasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 1)
            XCTAssertEqual(tasks[0].id, "t1")
        } else {
            XCTFail("Expected .jsonTasks, got \(String(describing: result))")
        }
    }

    func testExtractReviewTasksJSON_fromBareArray() {
        let text = """
        Analysis done. [{"id":"t1","description":"Fix","files":["a.swift"],"severity":"warning"}]
        """
        let result = CodeReviewMultiSwarmProvider.extractReviewTasksJSON(from: text)
        if case .jsonTasks(let tasks) = result {
            XCTAssertEqual(tasks.count, 1)
        } else {
            XCTFail("Expected .jsonTasks from bare array")
        }
    }

    func testExtractReviewTasksJSON_noJSON() {
        let result = CodeReviewMultiSwarmProvider.extractReviewTasksJSON(from: "No tasks here")
        XCTAssertNil(result)
    }

    func testExtractReviewTasksJSON_prefersLastCodeBlock() {
        let text = """
        ```json
        [{"id":"old","description":"Old","files":["a.swift"],"severity":"warning"}]
        ```

        Updated:

        ```json
        [{"id":"new","description":"New","files":["b.swift"],"severity":"critical"}]
        ```
        """
        let result = CodeReviewMultiSwarmProvider.extractReviewTasksJSON(from: text)
        if case .jsonTasks(let tasks) = result {
            XCTAssertEqual(tasks[0].id, "new")
        } else {
            XCTFail("Expected .jsonTasks with 'new' id")
        }
    }
}
