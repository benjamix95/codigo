import XCTest
@testable import CoderIDE

final class ChatPanelPipelineSnapshotRefreshPolicyTests: XCTestCase {
    func testPipelineSnapshotChangeRefreshPlanSkipsMessagesRefresh() {
        let plan = chatPanelPipelineSnapshotChangeRefreshPlan()

        XCTAssertTrue(plan.refreshChromeRuntimeSnapshot)
        XCTAssertFalse(plan.refreshMessagesSnapshot)
    }
}
