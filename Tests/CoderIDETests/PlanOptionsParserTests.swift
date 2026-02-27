import XCTest
@testable import CoderIDE

final class PlanOptionsParserTests: XCTestCase {
    func testParseOptionsWithMarkdownHeader() {
        let input = """
        ## Option 1: Refactor parser
        - Pro: robustness

        ## Option 2: Minimal patch
        - Pro: faster rollout
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].id, 1)
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("Refactor"))
        XCTAssertEqual(options[1].id, 2)
    }

    func testParseEnglishOptionsCaseInsensitive() {
        let input = """
        ## OPTION 1: Use strategy pattern
        details...

        ## option 2 - Keep current architecture
        details...
        """

        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options.map(\.id), [1, 2])
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("strategy"))
    }

    func testParseSupportsApproachVariantAndLetterIndex() {
        let input = """
        ### Approach A: Full refactor
        details...

        ### Approach 2 - Incremental patch
        details...
        """
        let options = PlanOptionsParser.parse(from: input)
        XCTAssertEqual(options.count, 2)
        XCTAssertTrue(options[0].title.localizedCaseInsensitiveContains("refactor"))
    }

    func testParseStrictIgnoresInlineNarrativeOptionToken() {
        let input = """
        Comparison summary: Option 2: keep current architecture for now.
        This is plain narrative text and should not create structured plan options.
        """

        let strict = PlanOptionsParser.parseStrict(from: input)
        XCTAssertTrue(strict.isEmpty)
    }

    func testParseStrictIgnoresOptionHeadersInsideCodeFences() {
        let input = """
        ## Option 1: Real option
        ## Todo
        - [ ] Implement step

        ```markdown
        ## Option 2: This is example code, not a real option
        ## Todo
        - [ ] Fake step
        ```
        """

        let strict = PlanOptionsParser.parseStrict(from: input)
        XCTAssertEqual(strict.count, 1)
        XCTAssertEqual(strict.first?.id, 1)
    }

    func testParseClarificationQuestionsReturnsQuestions() {
        let input = """
        Need more details.
        ## Questions
        1. Which system area must be modified?
        2. Are there backward-compatibility constraints?
        3. Do you prefer refactor or patch?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertNotNil(questions)
        XCTAssertEqual(questions?.count ?? 0, 3)
        XCTAssertEqual(questions?[0], "Which system area must be modified?")
        XCTAssertEqual(questions?[1], "Are there backward-compatibility constraints?")
    }

    func testParseClarificationQuestionsReturnsNilWhenNoBlock() {
        let input = """
        ## Option 1: Refactor
        - Pro: robustness
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertNil(questions)
    }

    func testParseClarificationQuestionsReturnsOneQuestionWhenPresent() {
        let input = """
        ## Questions
        1. One single question?
        """
        let questions = PlanOptionsParser.parseClarificationQuestions(from: input)
        XCTAssertEqual(questions, ["One single question?"])
    }

    func testParseStrictRejectsGenericNonPlanText() {
        let input = "I analyzed the project, but cannot propose options yet."
        let options = PlanOptionsParser.parseStrict(from: input)
        XCTAssertTrue(options.isEmpty)
    }

    func testParseFallsBackForDisplayEvenWhenStrictRejects() {
        let input = "Free-form response without formal structure."
        let strict = PlanOptionsParser.parseStrict(from: input)
        let display = PlanOptionsParser.parse(from: input)
        XCTAssertTrue(strict.isEmpty)
        XCTAssertEqual(display.count, 0)
    }

    func testTodoHeaderDetectionAcceptsAlternativeHeaders() {
        let input = "### Checklist\n- [ ] Review implementation\n- [ ] Update tests"
        XCTAssertTrue(PlanOptionsParser.hasRequiredTodoHeader(input))
        XCTAssertTrue(
            PlanOptionsParser.isTodoCompliantOption(
                PlanOption(id: 1, title: "Option 1", fullText: input)
            )
        )
    }

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

    func testExtractTodosFromOptionText() {
        let input = """
        ## Option 1: Refactor
        - Pro: robustness
        ## Todo
        - [ ] Step 1: Create interface
        - [ ] Step 2: Implement concrete class
        - [ ] Step 3: Update tests
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 3)
        XCTAssertEqual(todos[0], "Step 1: Create interface")
        XCTAssertEqual(todos[1], "Step 2: Implement concrete class")
        XCTAssertEqual(todos[2], "Step 3: Update tests")
    }

    func testExtractTodosFromOptionTextWithBullets() {
        let input = """
        ## Todo
        - First task
        - Second task
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos.count, 2)
    }

    func testExtractTodosFromOptionTextWithNonH2TodoHeader() {
        let input = """
        ### To-do
        - [ ] First task
        - [ ] Second task
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos, ["First task", "Second task"])
    }

    func testExtractTodosFromOptionTextFallsBackToChecklistWithoutHeader() {
        let input = """
        Option details:
        - [ ] First task
        - [ ] Second task
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertEqual(todos, ["First task", "Second task"])
    }

    func testExtractTodosFromOptionTextReturnsEmptyWhenNoSection() {
        let input = """
        ## Option 1: Refactor
        - Pro: robustness
        """
        let todos = PlanOptionsParser.extractTodosFromOptionText(input)
        XCTAssertTrue(todos.isEmpty)
    }

    func testExtractFinalPlanBodyExcludingQuestionsOptionsTodos() {
        let input = """
        ## Questions
        1. Do you prefer A or B?
        A) A
        B) B

        ## Option 1: Quick patch
        Option text.

        ## Todo
        - [ ] Step one

        ## Cause
        - overflow in composer on narrow width
        - markdown parsing too dense

        ## Approach
        Apply ViewThatFits + display-only layout normalization.
        """

        let output = PlanOptionsParser.extractFinalPlanBodyExcludingQuestionsOptionsTodos(input)

        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Questions"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Option"))
        XCTAssertFalse(output.localizedCaseInsensitiveContains("## Todo"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("## Cause"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("## Approach"))
    }

    func testExtractMermaidBlocksForDisplay() {
        let input = """
        ## Diagram
        ```mermaid
        graph TD
            A[Start] --> B[Build]
        ```
        """

        let blocks = PlanOptionsParser.extractMermaidBlocksForDisplay(input)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(blocks[0].contains("graph TD"))
    }
}
