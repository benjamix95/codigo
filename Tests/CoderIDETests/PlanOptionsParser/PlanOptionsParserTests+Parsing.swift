import XCTest
@testable import CoderIDE

extension PlanOptionsParserTests {
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
}
