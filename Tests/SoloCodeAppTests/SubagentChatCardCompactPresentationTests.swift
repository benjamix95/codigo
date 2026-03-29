import XCTest
@testable import CoderIDE

final class SubagentChatCardCompactPresentationTests: XCTestCase {
    func testCompactPreviewUsesLatestNonEmptyTranscriptEntries() {
        let result = SubagentChatCardCompactPresentation.compactPreviewText(
            from: ["uno", " ", "due", "tre", "quattro"],
            suffixCount: 3
        )

        XCTAssertEqual(result, "due\ntre\nquattro")
    }

    func testCompactPreviewUsesLatestNonEmptyLiveLines() {
        let result = SubagentChatCardCompactPresentation.compactPreviewText(
            from: """
            start

              read file
            write file
            """,
            suffixCount: 2
        )

        XCTAssertEqual(result, "read file\nwrite file")
    }
}
