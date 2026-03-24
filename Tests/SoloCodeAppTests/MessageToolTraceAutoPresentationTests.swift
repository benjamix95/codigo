import XCTest
@testable import CoderIDE

final class MessageToolTraceAutoPresentationTests: XCTestCase {
    func testReconcileDoesNotAutoExpandWhileRunning() {
        let current = MessageToolTraceAutoPresentationState(
            isExpanded: false,
            didAutoCompactAfterCompletion: true,
            userDidManuallyExpand: false,
            userDidManuallyCollapseWhileRunning: false,
            isCompactDiffExpanded: false,
            isCompactDiffLoading: false
        )

        let next = MessageToolTraceAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: true,
            hasOrderedEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertFalse(next.didAutoCompactAfterCompletion)
    }

    func testReconcileAutoCompactsOnceAfterCompletion() {
        let current = MessageToolTraceAutoPresentationState(
            isExpanded: true,
            didAutoCompactAfterCompletion: false,
            userDidManuallyExpand: true,
            userDidManuallyCollapseWhileRunning: true,
            isCompactDiffExpanded: true,
            isCompactDiffLoading: true
        )

        let next = MessageToolTraceAutoPresentation.reconcile(
            current: current,
            hasRunningEvent: false,
            hasOrderedEvents: true
        )

        XCTAssertFalse(next.isExpanded)
        XCTAssertTrue(next.didAutoCompactAfterCompletion)
        XCTAssertFalse(next.userDidManuallyExpand)
        XCTAssertFalse(next.userDidManuallyCollapseWhileRunning)
        XCTAssertFalse(next.isCompactDiffExpanded)
        XCTAssertFalse(next.isCompactDiffLoading)
    }

    func testCompactDiffNeverAutoExpands() {
        XCTAssertFalse(
            MessageToolTraceAutoPresentation.shouldAutoExpandCompactDiff(
                isTraceExpanded: true,
                hasPreview: true
            )
        )
    }
}
