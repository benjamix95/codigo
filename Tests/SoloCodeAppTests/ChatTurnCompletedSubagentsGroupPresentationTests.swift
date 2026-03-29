import XCTest
@testable import CoderIDE

final class ChatTurnCompletedSubagentsGroupPresentationTests: XCTestCase {
    func testInitialExpansionStateStartsCollapsed() {
        let state = ChatTurnCompletedSubagentsGroupExpansionState.initial(hasCards: true)

        XCTAssertFalse(state.isExpanded)
    }

    func testExpansionStateToggleExpandsAndCollapses() {
        var state = ChatTurnCompletedSubagentsGroupExpansionState.initial(hasCards: true)

        state.toggle()
        XCTAssertTrue(state.isExpanded)

        state.toggle()
        XCTAssertFalse(state.isExpanded)
    }

    func testPresentationBuildsTitleBadgeAndStatusSummary() {
        let group = ChatTurnCompletedSubagentsGroup(
            id: "completed-subagents-1",
            cards: [
                makeSnapshot(swarmId: "sa-review", title: "Reviewer", status: .completed),
                makeSnapshot(swarmId: "sa-security", title: "Security", status: .failed),
                makeSnapshot(swarmId: "sa-tests", title: "Tests", status: .completed),
            ],
            sequence: 1
        )

        let presentation = ChatTurnCompletedSubagentsGroupPresentation.make(group: group)

        XCTAssertEqual(presentation.title, "Sub-agent utilizzati")
        XCTAssertEqual(presentation.badgeText, "3")
        XCTAssertEqual(presentation.subtitle, "2 completati · 1 fallito")
    }

    private func makeSnapshot(
        swarmId: String,
        title: String,
        status: SwarmCardStatus
    ) -> SubagentCardSnapshot {
        SubagentCardSnapshot(
            swarmId: swarmId,
            status: status,
            title: title,
            detail: "done",
            summary: nil,
            errorCount: status == .failed ? 1 : 0,
            warningCount: 0,
            resultPreview: nil,
            transcript: nil
        )
    }
}
