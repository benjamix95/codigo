import XCTest
@testable import CoderIDE

final class ReviewPanelChatMessageContextTests: XCTestCase {
    func testExtractsUniqueFileTargetsFromSummaryContent() {
        let content = """
        ## Code Review Summary
        - [warning] Sources/App/Main.swift:42 — Something happened
        - [critical] Sources/App/Main.swift:42 — Duplicate reference
        - [info] Sources/Feature/PanelView.swift:7 — Another file
        """

        let targets = ReviewPanelChatMessageContext.fileTargets(from: content)

        XCTAssertEqual(
            targets,
            [
                ReviewPanelChatMessageFileTarget(
                    path: "Sources/App/Main.swift",
                    line: 42
                ),
                ReviewPanelChatMessageFileTarget(
                    path: "Sources/Feature/PanelView.swift",
                    line: 7
                ),
            ]
        )
    }

    func testExtractsFindingTargetsFromStatusMessages() {
        let content = """
        Fix applied to finding r1-worker-1.
        Finding r1-worker-1 dismissed.
        Another update for finding f-2.
        """

        let targets = ReviewPanelChatMessageContext.findingTargets(from: content)

        XCTAssertEqual(
            targets,
            [
                ReviewPanelChatFindingTarget(findingId: "r1-worker-1"),
                ReviewPanelChatFindingTarget(findingId: "f-2"),
            ]
        )
    }

    func testExtractsFindingTargetsFromStructuredFindingCards() {
        let content = """
        id: review-f-1
        finding_id: review-f-2
        """

        let targets = ReviewPanelChatMessageContext.findingTargets(from: content)

        XCTAssertEqual(
            targets,
            [
                ReviewPanelChatFindingTarget(findingId: "review-f-1"),
                ReviewPanelChatFindingTarget(findingId: "review-f-2"),
            ]
        )
    }
}
