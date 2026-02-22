import XCTest
@testable import CoderIDE

final class PlanOutputClassifierTests: XCTestCase {
    func testClassifyMixedClarificationAndOptionsPrefersProposalReady() {
        let input = """
        ## Domande di chiarimento
        1. Quale modulo?

        ## Opzione 1: Refactor
        - Pro: robusto

        ## Opzione 2: Patch
        - Pro: veloce

        ## Todo
        - [ ] Step 1
        """

        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .discovery,
            coderMode: .plan,
            shouldRunPlanInline: false
        )

        XCTAssertTrue(result.hasClarificationQuestions)
        XCTAssertTrue(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .proposalReady)
        guard case .awaitingChoice = result.planningState else {
            return XCTFail("planningState should be awaitingChoice")
        }
    }

    func testClassifyClarificationsOnlySetsAwaitingClarification() {
        let input = """
        ## Domande di chiarimento
        1. Quale modulo?
        2. Quali vincoli?
        """
        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .discovery,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertTrue(result.hasClarificationQuestions)
        XCTAssertFalse(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .awaitingClarification)
        guard case .awaitingClarification = result.planningState else {
            return XCTFail("planningState should be awaitingClarification")
        }
    }
}
