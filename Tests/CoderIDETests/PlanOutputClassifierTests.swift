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
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )

        // With the priority flip, clarification questions now take precedence over options
        XCTAssertTrue(result.hasClarificationQuestions)
        XCTAssertTrue(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .questioning)
        guard case .awaitingClarification = result.planningState else {
            return XCTFail("planningState should be awaitingClarification (clarification takes priority)")
        }
    }

    func testClassifyClarificationsOnlySetsQuestioning() {
        let input = """
        ## Domande di chiarimento
        1. Quale modulo?
        2. Quali vincoli?
        """
        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertTrue(result.hasClarificationQuestions)
        XCTAssertFalse(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .questioning)
        guard case .awaitingClarification = result.planningState else {
            return XCTFail("planningState should be awaitingClarification")
        }
    }

    func testClassifyFreeformPlanFallsBackToAwaitingChoice() {
        let input = """
        Piano consigliato:
        1. Analizza i moduli coinvolti.
        2. Applica il refactor in sicurezza.
        3. Esegui build e test.
        """
        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertFalse(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .proposalReady)
        guard case .awaitingChoice(_, let options) = result.planningState else {
            return XCTFail("planningState should be awaitingChoice")
        }
        XCTAssertEqual(options.count, 1)
        XCTAssertTrue(PlanOptionsParser.isFallbackOption(options[0]))
    }
}
