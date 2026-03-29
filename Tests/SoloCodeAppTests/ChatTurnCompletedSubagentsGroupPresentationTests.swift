import XCTest
@testable import CoderIDE

final class ChatTurnCompletedSubagentsGroupPresentationTests: XCTestCase {
    func testInitialExpansionStateStartsExpandedWhenRunningEntriesExist() {
        let state = ChatTurnCompletedSubagentsGroupExpansionState.initial(
            hasEntries: true,
            hasRunningEntries: true
        )

        XCTAssertTrue(state.isExpanded)
    }

    func testExpansionStateToggleExpandsAndCollapses() {
        var state = ChatTurnCompletedSubagentsGroupExpansionState.initial(
            hasEntries: true,
            hasRunningEntries: false
        )

        state.toggle()
        XCTAssertTrue(state.isExpanded)

        state.toggle()
        XCTAssertFalse(state.isExpanded)
    }

    func testPresentationBuildsTitleBadgeAndStatusSummary() {
        let group = ChatTurnCompletedSubagentsGroup(
            id: "completed-subagents-1",
            entries: [
                ChatTurnCompletedSubagentsGroupEntry(
                    snapshot: makeSnapshot(swarmId: "sa-review", title: "Reviewer", status: .running),
                    liveCard: SwarmLiveCardState(
                        swarmId: "sa-review",
                        displayName: "Reviewer",
                        roleType: "reviewer",
                        status: .running
                    )
                ),
                ChatTurnCompletedSubagentsGroupEntry(
                    snapshot: makeSnapshot(swarmId: "sa-security", title: "Security", status: .failed)
                ),
                ChatTurnCompletedSubagentsGroupEntry(
                    snapshot: makeSnapshot(swarmId: "sa-tests", title: "Tests", status: .completed)
                ),
            ],
            sequence: 1
        )

        let presentation = ChatTurnCompletedSubagentsGroupPresentation.make(group: group)

        XCTAssertEqual(presentation.title, "sub-agents")
        XCTAssertEqual(presentation.badgeText, "3")
        XCTAssertEqual(presentation.subtitle, "1 in esecuzione · 1 completato · 1 fallito")
    }

    func testReconcileAutoCollapsesWhenRunningEntriesFinish() {
        let current = ChatTurnCompletedSubagentsGroupExpansionState.initial(
            hasEntries: true,
            hasRunningEntries: true
        )

        let next = ChatTurnCompletedSubagentsGroupPresentation.reconcile(
            current: current,
            hasEntries: true,
            hasRunningEntries: false
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertTrue(next.didAutoCollapseAfterCompletion)
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
