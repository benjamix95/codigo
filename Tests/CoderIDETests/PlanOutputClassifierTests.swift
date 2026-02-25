import XCTest
@testable import CoderIDE

final class PlanOutputClassifierTests: XCTestCase {
    func testClassifyMixedClarificationAndOptionsPrefersProposalReady() {
        let input = """
        ## Questions
        1. Which module?

        ## Option 1: Refactor
        ## Todo
        - [ ] Step 1
        - [ ] Step 2

        ## Option 2: Patch
        ## Todo
        - [ ] Step A
        - [ ] Step B
        """

        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )

        // Clarification questions have priority even if options are present.
        XCTAssertTrue(result.hasClarificationQuestions)
        XCTAssertTrue(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .questioning)
        guard case .awaitingClarification = result.planningState else {
            return XCTFail("planningState should be awaitingClarification (clarification takes priority)")
        }
    }

    func testClassifyClarificationsOnlySetsQuestioning() {
        let input = """
        ## Questions
        1. Which module?
        2. Which constraints?
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

    func testClassifyFreeformPlanWithoutTodoCompliantOptionsKeepsCurrentPhase() {
        let input = """
        Recommended plan:
        1. Analyze the involved modules.
        2. Apply the refactor safely.
        3. Run build and tests.
        """
        let result = PlanOutputClassifier.classify(
            fullText: input,
            current: .analyzing,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertFalse(result.hasStrictOptions)
        XCTAssertEqual(result.nextPhase, .analyzing)
        XCTAssertNil(result.planningState)
    }
}
