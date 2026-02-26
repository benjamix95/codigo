import XCTest
@testable import CoderIDE

final class PlanQuestionPhaseDecisionTests: XCTestCase {
    func testNoQuestionsNeededSignalIsCaseAndPunctuationTolerant() {
        XCTAssertTrue(hasNoQuestionsNeededSignal("NO_QUESTIONS_NEEDED"))
        XCTAssertTrue(hasNoQuestionsNeededSignal("no_questions_needed"))
        XCTAssertTrue(hasNoQuestionsNeededSignal("No_Questions_Needed."))
        XCTAssertTrue(hasNoQuestionsNeededSignal("  NO_QUESTIONS_NEEDED!  "))
        XCTAssertTrue(hasNoQuestionsNeededSignal("No questions needed"))
        XCTAssertFalse(hasNoQuestionsNeededSignal("I still need clarifications"))
    }

    func testQuestionPhaseDecisionReturnsClarificationForStructuredQuestions() {
        let text = """
        ## Questions
        1. Which module?
        A) Parser
        B) UI
        """

        let decision = decidePlanQuestionPhaseOutput(
            text,
            coderMode: .plan,
            shouldRunPlanInline: false
        )

        if case .clarification(let questions) = decision {
            XCTAssertTrue(questions.contains("## Questions"))
        } else {
            XCTFail("Expected clarification decision")
        }
    }

    func testQuestionPhaseDecisionProceedsOnUnstructuredOutput() {
        let text = "I have enough context now and can move to plan generation."
        let decision = decidePlanQuestionPhaseOutput(
            text,
            coderMode: .plan,
            shouldRunPlanInline: false
        )
        XCTAssertEqual(decision, .proceedToGeneration)
    }
}
