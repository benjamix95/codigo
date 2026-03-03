import XCTest
@testable import CoderIDE

extension PlanOptionsParserTests {
    func testParseClarificationQuestionsSupportsLevelThreeHeader() {
        let input = """
        ### Questions:
        1. Which module should be updated?
        2. Which behavior must be preserved?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertEqual(questions?.count, 2)
        XCTAssertEqual(questions?.first, "Which module should be updated?")
    }

    func testParseClarificationQuestionsSupportsMixedBulletsAndNumbers() {
        let input = """
        ## Clarification Questions
        - What is the primary target?
        2. Which tests already exist?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertEqual(questions?.count, 2)
        XCTAssertEqual(questions?[0], "What is the primary target?")
        XCTAssertEqual(questions?[1], "Which tests already exist?")
    }

    func testParseClarificationQuestionsStopsAtAnyMarkdownHeading() {
        let input = """
        # Clarification Questions
        - Which module?
        - Which constraint?
        # Option 1
        - This bullet is not a clarification question
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertEqual(questions?.count, 2)
        XCTAssertEqual(questions?[0], "Which module?")
        XCTAssertEqual(questions?[1], "Which constraint?")
    }

    func testParseClarificationQuestionnaireStructuredQuestionsAndOptions() {
        let input = """
        ## Questions
        1. What is the primary objective?
        A) Improve performance
        B) Fix bugs
        C) Improve DX

        2. Which priority do you want?
        A) High
        B) Medium
        """

        let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: input)
        XCTAssertNotNil(questionnaire)
        XCTAssertEqual(questionnaire?.questions.count, 2)
        XCTAssertEqual(questionnaire?.questions[0].prompt, "What is the primary objective?")
        XCTAssertEqual(questionnaire?.questions[0].options.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(questionnaire?.questions[1].options.map(\.text), ["High", "Medium"])
    }

    func testParseClarificationQuestionnaireReturnsNilWhenOptionsMissing() {
        let input = """
        ## Questions
        1. Which module should be touched?
        """

        let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: input)
        XCTAssertNil(questionnaire)
    }

    func testIsOtherLikeClarificationOptionMatchesKeywordsCaseAndDiacritics() {
        XCTAssertTrue(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "I", text: "Other...")
            )
        )
        XCTAssertTrue(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "L", text: "Óther (specify in input)")
            )
        )
        XCTAssertTrue(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "M", text: "Specify custom details")
            )
        )
        XCTAssertTrue(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "N", text: "Specify in the field below")
            )
        )
    }

    func testIsOtherLikeClarificationOptionRejectsClosedOptions() {
        XCTAssertFalse(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "H", text: "No specific priority")
            )
        )
        XCTAssertFalse(
            PlanOptionsParser.isOtherLikeClarificationOption(
                PlanClarificationOption(id: "Z", text: "Motherboard compatibility")
            )
        )
    }

    func testParseFallbackDoesNotTreatNumberedLinesInsideCodeFencesAsPlanSignals() {
        let input = """
        ```markdown
        1. First line inside code fence
        2. Second line inside code fence
        ```
        """

        let parsed = PlanOptionsParser.parse(from: input)
        XCTAssertTrue(parsed.isEmpty)
    }
}
