import XCTest
@testable import CoderIDE

final class TodoExecutionFollowUpPolicyTests: XCTestCase {
    func testNormalizeExecutionTitlesAppendsReviewAndDocWriterAtEnd() {
        let titles = TodoExecutionFollowUpPolicy.normalizeExecutionTitles([
            "Implementare fix",
            "Aggiornare test",
        ])

        XCTAssertEqual(
            titles,
            [
                "Implementare fix",
                "Aggiornare test",
                "Code Review & Test",
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
                "Implementare fix",
                "Code Review & Test",
                "Doc Writer",
            ]
        )
    }
}
