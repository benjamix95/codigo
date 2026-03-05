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

    func testParseClarificationQuestionnaireDetectsInlineMultiSelectMarkerWithoutParentheses() {
        let input = """
        ## Questions
        1. Seleziona i target select all that apply
        A) iOS
        B) macOS
        """

        let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: input)
        XCTAssertEqual(questionnaire?.questions.count, 1)
        XCTAssertEqual(questionnaire?.questions.first?.prompt, "Seleziona i target")
        XCTAssertEqual(questionnaire?.questions.first?.isMultiSelect, true)
    }

    func testQuestionnaireMarkdownRoundTripPreservesInlineMultiSelectPrompt() {
        let questionnaire = PlanClarificationQuestionnaire(
            questions: [
                PlanClarificationQuestion(
                    id: 1,
                    prompt: "Scegli i moduli select all that apply",
                    options: [
                        PlanClarificationOption(id: "A", text: "Parser"),
                        PlanClarificationOption(id: "B", text: "UI"),
                    ],
                    isMultiSelect: true
                ),
            ]
        )

        let markdown = PlanClarificationQuestionnaireMarkdown.render(questionnaire: questionnaire)
        let parsed = PlanOptionsParser.parseClarificationQuestionnaire(from: markdown)
        XCTAssertEqual(parsed?.questions.count, 1)
        XCTAssertEqual(parsed?.questions.first?.isMultiSelect, true)
        XCTAssertEqual(parsed?.questions.first?.prompt, "Scegli i moduli")
    }

    func testParseClarificationQuestionnaireSupportsNumericOptionIdentifiers() {
        let input = """
        ## Questions
        1. Quale scope preferisci?
        1) Solo fix critici
        2) Fix + test
        3) Refactor esteso
        """

        let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: input)
        XCTAssertEqual(questionnaire?.questions.count, 1)
        XCTAssertEqual(questionnaire?.questions.first?.options.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(
            questionnaire?.questions.first?.options.map(\.text),
            ["Solo fix critici", "Fix + test", "Refactor esteso"]
        )
    }

    func testParseClarificationQuestionnaireSupportsBulletOptionsWithoutExplicitIds() {
        let input = """
        ## Questions
        1. Quale strategia vuoi seguire?
        - Incrementale (Recommended)
        - Other (specify)
        """

        let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: input)
        XCTAssertEqual(questionnaire?.questions.count, 1)
        let options = questionnaire?.questions.first?.options ?? []
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.map(\.id), ["A", "B"])
        XCTAssertEqual(options.map(\.text), ["Incrementale", "Other (specify)"])
        XCTAssertEqual(options.map(\.isRecommended), [true, false])
    }
}
