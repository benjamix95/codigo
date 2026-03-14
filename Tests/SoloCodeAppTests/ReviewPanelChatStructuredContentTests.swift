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
        XCTAssertEqual(sections.last?.style, .outcome)
    }

    func testReviewRunSectionsAssignUniqueSectionIDsWhenHeadersRepeat() {
        let message = ReviewPanelMessage(
            role: .assistant,
            kind: .reviewRun,
            content: """
            ### Planned Work
            - [ ] Check Main.swift for regressions
            ### Planned Work
            - [ ] Check Main.swift for regressions
            """
        )

        let sections = ReviewPanelChatStructuredContent.sections(for: message)

        XCTAssertEqual(sections.map(\.id), ["planned-work-0", "planned-work-1"])
    }

    func testStructuredSectionsExposeUniqueDisplayLineIDsForDuplicateLines() {
        let section = ReviewPanelChatStructuredSection(
            id: "metadata",
            title: "Session",
            lines: [
                "mcp_tool_call: 1│import Foundation",
                "mcp_tool_call: 1│import Foundation",
                "3│## Bug Fix Record",
                "3│## Bug Fix Record",
            ],
            style: .metadata,
            isInitiallyExpanded: true
        )

        let displayLines = section.displayLines

        XCTAssertEqual(displayLines.map(\.text), section.lines)
        XCTAssertEqual(Set(displayLines.map(\.id)).count, section.lines.count)
        XCTAssertEqual(displayLines.map(\.id), [
            "metadata-line-0",
            "metadata-line-1",
            "metadata-line-2",
            "metadata-line-3",
        ])
    }

    func testChatContextPromptEnforcesBugSecurityAndMarkdownStructure() {
        let conversationId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")
        let prompt = ReviewPanelCoordinator.chatContextPrompt(
            userMessage: "controlla la sessione corrente",
            sessionSummary: "Phase: running\nScope: uncommitted",
            findingsCount: 3,
            openCount: 2,
            activeSessionId: "review-session-1",
            conversationId: conversationId
        )

        XCTAssertTrue(prompt.contains("primary focus is bug hunting"))
        XCTAssertTrue(prompt.contains("security review"))
        XCTAssertTrue(prompt.contains("full tool-enabled review environment"))
        XCTAssertTrue(prompt.contains("Use well-structured markdown"))
        XCTAssertTrue(prompt.contains("## Findings"))
        XCTAssertTrue(prompt.contains("review_findings"))
        XCTAssertTrue(prompt.contains("review-session-1"))
        XCTAssertTrue(prompt.contains(conversationId?.uuidString ?? ""))
        XCTAssertTrue(prompt.contains("Reuse the current active review session"))
        XCTAssertTrue(prompt.contains("Do not call `review_start` unless the user explicitly asks"))
        XCTAssertTrue(prompt.contains("always pass `session_id` and `conversation_id`"))
    }

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

@MainActor
final class ReviewPanelChatAutoscrollTests: XCTestCase {
    func testMessageListFingerprintChangesWhenStructuredPresentationGrows() {
        let messageId = UUID()
        let base = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "### Activity\nReview stream started",
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "activity",
                        title: "Activity",
                        lines: ["Review stream started"],
                        style: .log,
                        isInitiallyExpanded: true
                    )
                ]
            ),
            isStreaming: true
        )

        let updated = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: base.content,
            presentation: ReviewPanelMessagePresentation(
                sections: [
                    ReviewPanelChatStructuredSection(
                        id: "activity",
                        title: "Activity",
                        lines: [
                            "Review stream started",
                            "mcp_tool_call: MCP call • coderide/coderide_skill",
                        ],
                        style: .log,
                        isInitiallyExpanded: true
                    )
                ]
            ),
            isStreaming: true
        )

        let before = ReviewPanelChatAutoscroll.messageListFingerprint([base])
        let after = ReviewPanelChatAutoscroll.messageListFingerprint([updated])

        XCTAssertNotEqual(before, after)
    }

    func testMessageListFingerprintChangesWhenStreamingStateFlips() {
        let messageId = UUID()
        let streaming = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "done",
            isStreaming: true
        )
        let completed = ReviewPanelMessage(
            id: messageId,
            role: .assistant,
            kind: .reviewRun,
            content: "done",
            isStreaming: false
        )

        XCTAssertNotEqual(
            ReviewPanelChatAutoscroll.messageListFingerprint([streaming]),
            ReviewPanelChatAutoscroll.messageListFingerprint([completed])
        )
    }

    func testSectionLogFingerprintChangesWhenLastLineAdvances() {
        let initial = ReviewPanelChatStructuredSection(
            id: "activity",
            title: "Activity",
            lines: ["Review stream started"],
            style: .log,
            isInitiallyExpanded: true
        )
        let updated = ReviewPanelChatStructuredSection(
            id: "activity",
            title: "Activity",
            lines: [
                "Review stream started",
                "assistant_update: Sto facendo convergere anche il workflow del `skill`",
            ],
            style: .log,
            isInitiallyExpanded: true
        )

        XCTAssertNotEqual(
            ReviewPanelChatAutoscroll.sectionLogFingerprint(initial),
            ReviewPanelChatAutoscroll.sectionLogFingerprint(updated)
        )
    }
}
