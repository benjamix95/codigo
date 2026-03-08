import XCTest
import CoderEngine
@testable import CoderIDE

final class ReviewPanelChatMessageFactoryTests: XCTestCase {
    func testSummaryFactoryBuildsPrecomputedPresentation() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "f-1",
                    severity: .warning,
                    category: .bug,
                    filePath: "Sources/App/Main.swift",
                    message: "Something happened"
                )
            ],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .uncommitted, files: ["Sources/App/Main.swift"]),
            workspacePath: nil,
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: nil,
            completedAt: nil,
            analysisCompletedAt: nil,
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: nil,
            lastUpdatedAt: Date()
        )

        let message = ReviewPanelChatMessageFactory.summary(snapshot: snapshot)

        XCTAssertEqual(message.kind, .summary)
        XCTAssertEqual(message.presentation?.sections.map(\.title), ["Session", "Findings"])
    }

    func testFindingUpdateFactoryBuildsDedicatedSection() {
        let message = ReviewPanelChatMessageFactory.findingUpdate(
            text: "Fix applied to finding f-1."
        )

        XCTAssertEqual(message.kind, .findingMutation)
        XCTAssertEqual(message.presentation?.sections.first?.title, "Finding Update")
        XCTAssertEqual(message.presentation?.sections.first?.lines, ["Fix applied to finding f-1."])
    }
}
