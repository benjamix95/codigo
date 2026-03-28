import XCTest
@testable import CoderIDE

final class InlineToolTraceGroupAutoPresentationTests: XCTestCase {
    func testInitialStateKeepsRunningGroupsExpanded() {
        let state = InlineToolTraceGroupAutoPresentation.initialState(
            hasRunningEvent: true,
            hasEvents: true
        )

        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.didAutoCollapseAfterCompletion)
    }

    func testInitialStateCollapsesCompletedGroups() {
        let state = InlineToolTraceGroupAutoPresentation.initialState(
            hasRunningEvent: false,
            hasEvents: true
        )

        XCTAssertFalse(state.isExpanded)
        XCTAssertTrue(state.didAutoCollapseAfterCompletion)
    }

    func testReconcileAutoCollapsesWhenGroupCompletes() {
        let current = InlineToolTraceGroupAutoPresentationState(
            isExpanded: true,
            didAutoCollapseAfterCompletion: false
        )

        let next = InlineToolTraceGroupAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: false,
            hasEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertTrue(next.didAutoCollapseAfterCompletion)
    }

    func testReconcilePreservesManualReopenAfterAutoCollapse() {
        let current = InlineToolTraceGroupAutoPresentationState(
            isExpanded: true,
            didAutoCollapseAfterCompletion: true
        )

        let next = InlineToolTraceGroupAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: false,
            hasEvents: true
        )

        XCTAssertEqual(next, current)
    }

    func testReconcileResetsCompletionLatchWhenGroupRunsAgain() {
        let current = InlineToolTraceGroupAutoPresentationState(
            isExpanded: false,
            didAutoCollapseAfterCompletion: true
        )

        let next = InlineToolTraceGroupAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: true,
            hasEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertFalse(next.didAutoCollapseAfterCompletion)
    }
}
