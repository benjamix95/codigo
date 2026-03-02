import XCTest
@testable import CoderEngine

final class CodeReviewMultiSwarmProviderTests: XCTestCase {

    // MARK: - parseAgainstRef

    func testParseAgainstRef_withValidRef() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:abc123] Review my code")
        XCTAssertEqual(ref, "abc123")
        XCTAssertEqual(clean, "Review my code")
    }

    func testParseAgainstRef_withRefOnly() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:main]")
        XCTAssertEqual(ref, "main")
        XCTAssertEqual(clean, "Review all changes")
    }

    func testParseAgainstRef_withoutRef() {
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "Just review everything")
        XCTAssertNil(ref)
        XCTAssertEqual(clean, "Just review everything")
    }

    func testParseAgainstRef_trimsWhitespace() {
        let (_, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "[AGAINST:  HEAD~3  ] rest")
        XCTAssertEqual(ref, "HEAD~3")
    }

    func testParseAgainstRef_notAtStart() {
        // [AGAINST:...] must be at the start of the string
        let (clean, ref) = CodeReviewMultiSwarmProvider.parseAgainstRef(from: "prefix [AGAINST:abc] rest")
        XCTAssertNil(ref)
        XCTAssertEqual(clean, "prefix [AGAINST:abc] rest")
    }

    // MARK: - isValidAgainstRefFormat

    func testIsValidAgainstRefFormat_acceptsCommonRevisionExpressions() {
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("HEAD~1"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("main..feature"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("abc123def"))
        XCTAssertTrue(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("feature^"))
    }

    func testIsValidAgainstRefFormat_rejectsUnsafeOrInvalidInput() {
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(""))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(" "))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("--cached"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref with space"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref:path"))
        XCTAssertFalse(CodeReviewMultiSwarmProvider.isValidAgainstRefFormat("ref@{0}"))
    }

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

    // MARK: - gitDiffFiles argument order

    func testGitDiffFiles_invalidRef_returnsError() {
        // Use a non-existent directory to trigger a git error, confirming the
        // function surfaces errors correctly rather than silently returning empty.
        let bogusPath = URL(fileURLWithPath: "/tmp/nonexistent-repo-\(UUID().uuidString)")
        let (files, error) = CodeReviewMultiSwarmProvider.gitDiffFiles(ref: "HEAD~1", workspacePath: bogusPath)
        XCTAssertTrue(files.isEmpty)
        XCTAssertNotNil(error)
    }

    // MARK: - findingsContainIssues

    func testFindingsContainIssues_cleanPhraseOnly_returnsClean() {
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(
            for: "No issues found. Everything looks good."
        )
        XCTAssertEqual(state, "clean")
    }

    func testFindingsContainIssues_noCriticalIssuesPhrase_doesNotFalsePositive() {
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(
            for:
            "No critical issues found in the reviewed files."
        )
        XCTAssertEqual(state, "clean")
    }

    func testFindingsContainIssues_mixedCleanAndIssueText_returnsIssues() {
        let text = "No critical issues in module A, but a security vulnerability remains in auth flow."
        let state = CodeReviewMultiSwarmProvider.findingsStateDebugLabel(for: text)
        XCTAssertEqual(state, "issues")
    }

    // MARK: - worker ordering

    func testSortedWorkerTaskIDsForDisplay_usesNaturalOrdering() {
        let ids = ["review-10", "review-2", "review-1"]
        let sorted = CodeReviewMultiSwarmProvider.sortedWorkerTaskIDsForDisplay(ids)
        XCTAssertEqual(sorted, ["review-1", "review-2", "review-10"])
    }

    // MARK: - test failure output detection

    func testOutputSignalsTestFailure_ignoresGenericErrorToken() {
        let output = "Build completed. Notes: error: keyword appears in docs only."
        XCTAssertFalse(CodeReviewMultiSwarmProvider.outputSignalsTestFailure(output))
    }

    func testOutputSignalsTestFailure_detectsJestFailLine() {
        let output = """
        FAIL src/review/provider.test.ts
        Test Suites: 1 failed, 3 passed, 4 total
        """
        XCTAssertTrue(CodeReviewMultiSwarmProvider.outputSignalsTestFailure(output))
    }
}
