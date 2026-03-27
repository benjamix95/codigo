import XCTest
@testable import CoderIDE

final class TodoExecutionFollowUpPolicyTests: XCTestCase {
    func testNormalizeExecutionTitlesExpandsSingleImplementationIntoRealPhases() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Implementare fix",
        ])

        XCTAssertEqual(
            titles,
            [
                "Analizzare target",
                "Implementare fix",
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }

    func testNormalizeExecutionTitlesExpandsSingleAnalysisIntoRealPhases() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Scansionare il progetto per bug",
        ])

        XCTAssertEqual(
            titles,
            [
                "Definire scope",
                "Scansionare il progetto per bug",
                "Consolidare findings / output",
                "Doc Writer",
            ]
        )
    }

    func testNormalizeExecutionTitlesDropsOrphanFollowUpsWithoutExecutableSteps() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Code Review & Test",
            "Doc Writer",
        ])

        XCTAssertTrue(titles.isEmpty)
    }

    func testNormalizeExecutionTitlesDeduplicatesAndReordersFollowUps() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Implementare fix",
            "Doc Writer",
            "Code Review & Test",
            "Implementare fix",
        ])

        XCTAssertEqual(
            titles,
            [
                "Analizzare target",
                "Implementare fix",
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }

    func testNormalizeExecutionTitlesDropsPlaceholderTodos() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Task",
            "Step 1",
            "Analizzare dipendenze",
            "Doc Writer",
        ])

        XCTAssertEqual(
            titles,
            [
                "Definire scope",
                "Analizzare dipendenze",
                "Consolidare findings / output",
                "Doc Writer",
            ]
        )
    }
}
