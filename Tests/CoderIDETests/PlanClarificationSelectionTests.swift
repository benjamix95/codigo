import XCTest
@testable import CoderIDE

final class PlanClarificationSelectionTests: XCTestCase {
    func testOtherLikeOptionRequiresCustomText() {
        let question = PlanClarificationQuestion(
            id: 1,
            prompt: "Quale priorita?",
            options: [
                PlanClarificationOption(id: "A", text: "Other (specify)"),
                PlanClarificationOption(id: "B", text: "High"),
            ]
        )
        let other = question.options[0]

        XCTAssertFalse(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: other,
                customText: ""
            )
        )
        XCTAssertFalse(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: other,
                customText: "   "
            )
        )
        XCTAssertTrue(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: other,
                customText: "Priorita produzione"
            )
        )
    }

    func testRegularOptionDoesNotRequireCustomText() {
        let question = PlanClarificationQuestion(
            id: 2,
            prompt: "Quale area?",
            options: [
                PlanClarificationOption(id: "A", text: "Parser"),
                PlanClarificationOption(id: "B", text: "UI"),
            ]
        )
        let selected = question.options[0]

        XCTAssertTrue(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: selected,
                customText: nil
            )
        )
    }
}
