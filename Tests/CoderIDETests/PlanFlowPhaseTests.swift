import XCTest
@testable import CoderIDE

final class PlanFlowPhaseTests: XCTestCase {
    func testBuildBlockedWhenPhaseNotReady() {
        XCTAssertFalse(canExecutePlanBuild(phase: .analyzing, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .questioning, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .generating, choice: "Option 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .building, choice: "Option 1"))
    }

    func testPhaseTransitionsAnalyzingToQuestioning() {
        let text = """
        ## Questions
        1. Which module should be modified?
        A) Parser
        B) UI

        2. Are there compatibility constraints?
        A) Yes
        B) No
        """
        let phase = nextPlanFlowPhaseForOutput(
            fullText: text,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .questioning)
    }

    func testPhaseTransitionsProposalToReadyToBuildViaGating() {
        XCTAssertFalse(canExecutePlanBuild(phase: .idle, choice: "## Option 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .idle, choice: "## Option 1: A", allowIdleRebuild: true))
        XCTAssertTrue(canExecutePlanBuild(phase: .proposalReady, choice: "## Option 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .readyToBuild, choice: "## Option 1: A"))
    }

    func testCanStartPlanBuildBlocksConcurrentExecution() {
        XCTAssertFalse(canStartPlanBuild(isLoading: true, phase: .proposalReady))
        XCTAssertFalse(canStartPlanBuild(isLoading: false, phase: .building))
        XCTAssertTrue(canStartPlanBuild(isLoading: false, phase: .proposalReady))
    }

    func testPhaseStaysAnalyzingOnGenericTextWithoutTodoCompliantOptions() {
        let phase = nextPlanFlowPhaseForOutput(
            fullText: "Analysis complete, but more information is required.",
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .analyzing)
    }

    func testPanelBuildEnabledInIdleWhenChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true))
        XCTAssertTrue(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true, allowIdleRebuild: true))
    }

    func testPanelBuildDisabledInIdleWhenNoChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: false))
    }

}
