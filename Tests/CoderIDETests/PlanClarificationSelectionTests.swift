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

    func testMultiSelectWithOtherLikeOptionRequiresCustomText() {
        let question = PlanClarificationQuestion(
            id: 3,
            prompt: "Seleziona i target (select all that apply)",
            options: [
                PlanClarificationOption(id: "A", text: "iOS"),
                PlanClarificationOption(id: "B", text: "Other (specify)"),
                PlanClarificationOption(id: "C", text: "Android"),
            ],
            isMultiSelect: true
        )

        XCTAssertFalse(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: nil,
                selectedOptions: Set(["A", "B"]),
                customText: " "
            )
        )
        XCTAssertTrue(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: nil,
                selectedOptions: Set(["A", "B"]),
                customText: "Web/Desktop"
            )
        )
    }

    func testMultiSelectWithoutOtherLikeOptionDoesNotRequireCustomText() {
        let question = PlanClarificationQuestion(
            id: 4,
            prompt: "Seleziona stack",
            options: [
                PlanClarificationOption(id: "A", text: "SwiftUI"),
                PlanClarificationOption(id: "B", text: "UIKit"),
            ],
            isMultiSelect: true
        )

        XCTAssertTrue(
            isClarificationSelectionComplete(
                question: question,
                selectedOption: nil,
                selectedOptions: Set(["A"]),
                customText: nil
            )
        )
    }
}
