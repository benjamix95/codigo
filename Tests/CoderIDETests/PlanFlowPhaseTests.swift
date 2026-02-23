import XCTest
@testable import CoderIDE

final class PlanFlowPhaseTests: XCTestCase {
    func testBuildBlockedWhenPhaseNotReady() {
        XCTAssertFalse(canExecutePlanBuild(phase: .analyzing, choice: "Opzione 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .questioning, choice: "Opzione 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .generating, choice: "Opzione 1"))
        XCTAssertFalse(canExecutePlanBuild(phase: .building, choice: "Opzione 1"))
    }

    func testPhaseTransitionsAnalyzingToQuestioning() {
        let text = """
        ## Domande di chiarimento
        1. Quale modulo devo modificare?
        2. Ci sono vincoli di compatibilità?
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
        XCTAssertFalse(canExecutePlanBuild(phase: .idle, choice: "## Opzione 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .idle, choice: "## Opzione 1: A", allowIdleRebuild: true))
        XCTAssertTrue(canExecutePlanBuild(phase: .proposalReady, choice: "## Opzione 1: A"))
        XCTAssertTrue(canExecutePlanBuild(phase: .readyToBuild, choice: "## Opzione 1: A"))
    }

    func testCanStartPlanBuildBlocksConcurrentExecution() {
        XCTAssertFalse(canStartPlanBuild(isLoading: true, phase: .proposalReady))
        XCTAssertFalse(canStartPlanBuild(isLoading: false, phase: .building))
        XCTAssertTrue(canStartPlanBuild(isLoading: false, phase: .proposalReady))
    }

    func testPhaseTransitionsToProposalReadyOnGenericTextFallback() {
        let phase = nextPlanFlowPhaseForOutput(
            fullText: "Analisi completata, ma servono più informazioni.",
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(phase, .proposalReady)
    }

    func testPanelBuildEnabledInIdleWhenChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true))
        XCTAssertTrue(isPlanBuildEnabled(phase: .idle, hasBuildChoice: true, allowIdleRebuild: true))
    }

    func testPanelBuildDisabledInIdleWhenNoChoiceExists() {
        XCTAssertFalse(isPlanBuildEnabled(phase: .idle, hasBuildChoice: false))
    }

}
