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
            current: .discovery,
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

    func testAutoResetPlanningStateDoesNotClearAwaitingChoice() {
        XCTAssertFalse(
            shouldResetPlanningStateAfterAutoPlanToggleReset(
                planFlowPhase: .proposalReady,
                planningState: .awaitingChoice(planContent: "x", options: [])
            )
        )
    }

    func testAutoResetPlanningStateClearsIdleOrClarificationStates() {
        XCTAssertTrue(
            shouldResetPlanningStateAfterAutoPlanToggleReset(
                planFlowPhase: .discovery,
                planningState: .awaitingClarification(questions: "q")
            )
        )
        XCTAssertFalse(
            shouldResetPlanningStateAfterAutoPlanToggleReset(
                planFlowPhase: .building,
                planningState: .awaitingClarification(questions: "q")
            )
        )
    }
}
