import XCTest
@testable import CoderIDE

@MainActor
final class ReviewPanelChatStructuredContentTests: XCTestCase {
    func testSummarySectionsSplitMetadataAndFindings() {
        let message = ReviewPanelMessage(
            role: .system,
            kind: .summary,
            content: """
            ## Code Review Summary
            - session_id: session-1
            - phase: completed
            - findings: 2
            - [warning] Sources/App/Main.swift:42 — Something happened
            - [critical] Sources/App/Panel.swift:7 — Another issue
            """
        )

        let sections = ReviewPanelChatStructuredContent.sections(for: message)

        XCTAssertEqual(sections.map(\.title), ["Session", "Findings"])
        XCTAssertEqual(sections.first?.lines.count, 3)
        XCTAssertEqual(sections.last?.lines.count, 2)
    }

    func testReviewRunSectionsSplitLogAndVerdict() {
        let message = ReviewPanelMessage(
            role: .assistant,
            kind: .reviewRun,
            content: """
            worker-1 started
            worker-2 completed
            ---
            **Multi-swarm code review complete.** Tests passing. Re-review clean.
            """
        )

        let sections = ReviewPanelChatStructuredContent.sections(for: message)

        XCTAssertEqual(sections.map(\.title), ["Run Output", "Verdict"])
        XCTAssertEqual(sections.first?.style, .log)
        XCTAssertEqual(sections.last?.style, .prose)
    }

    func testChatContextPromptEnforcesBugSecurityAndMarkdownStructure() {
        let prompt = ReviewPanelCoordinator.chatContextPrompt(
            userMessage: "controlla la sessione corrente",
            sessionSummary: "Phase: running\nScope: uncommitted",
            findingsCount: 3,
            openCount: 2
        )

        XCTAssertTrue(prompt.contains("primary focus is bug hunting"))
        XCTAssertTrue(prompt.contains("security review"))
        XCTAssertTrue(prompt.contains("full tool-enabled review environment"))
        XCTAssertTrue(prompt.contains("Use well-structured markdown"))
        XCTAssertTrue(prompt.contains("## Findings"))
        XCTAssertTrue(prompt.contains("review_findings"))
    }
}
