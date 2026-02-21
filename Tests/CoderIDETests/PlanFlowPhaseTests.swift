import XCTest
@testable import CoderIDE

final class PlanFlowPhaseTests: XCTestCase {
    func testBuildBlockedWhenPhaseNotReady() {
        XCTAssertFalse(canExecutePlanBuild(phase: .discovery, choice: "Opzione 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .awaitingClarification, choice: "Opzione 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .building, choice: "Opzione 1"))
    }

    func testPhaseTransitionsDiscoveryToClarification() {
        let text = """
        ## Domande di chiarimento
        1. Quale modulo devo modificare?
        2. Ci sono vincoli di compatibilità?
        """
        let phase = nextPlanFlowPhaseForOutput(
            fullText: text,
            current: .discovery,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .awaitingClarification)
    }

    func testPhaseTransitionsProposalToReadyToBuildViaGating() {
        XCTAssertTrue(canExecutePlanBuild(phase: .idle, choice: "## Opzione 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .proposalReady, choice: "## Opzione 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .readyToBuild, choice: "## Opzione 1: A"))
    }

    func testPanelBuildEnabledInIdleWhenChoiceExists() {
        XCTAssertTrue(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true))
    }

    func testPanelBuildDisabledInIdleWhenNoChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: false))
    }
}
